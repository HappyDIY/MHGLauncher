import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { AppError } from "../core/errors";
import type { GameJob, GameState, JobKind } from "../core/models";
import type { Store } from "../core/database";
import type { GameBuild, Provider } from "../providers/provider";
import { DownloadControl, download } from "./download";
import { activate, extract, stageExisting, verify } from "./installer";
import { installSophon } from "./sophon-install";
import { installPatches } from "./patch-install";
import { prepareBuild, removeRetired, removeSafe } from "./game-build";

export class GameService {
  private readonly jobs = new Map<string, GameJob>();
  private readonly controls = new Map<string, DownloadControl>();
  constructor(private readonly store: Store, private readonly provider: Provider, private readonly dataDir: string) {}

  busy(): boolean {
    return [...this.jobs.values()].some(({ status }) => ["queued", "running", "paused"].includes(status));
  }

  async state(requested?: string): Promise<GameState> {
    const stored = this.store.one("SELECT install_path FROM game_state WHERE id=1");
    const candidate = requested || String(stored?.install_path ?? "");
    const detected = candidate ? detectGame(candidate) : null;
    const raw = await this.provider.getBuild(detected?.version ?? "");
    const build = detected ? prepareBuild(raw, detected.path, detected.version) : raw;
    if (!detected) return output(candidate, "", build, "not_installed");
    this.saveState(detected.path, detected.version);
    const current = detected.version === build.version && !build.assets.length;
    return output(detected.path, detected.version, build, current ? "ready" : "update_available");
  }

  async start(kind: JobKind, path: string): Promise<GameJob> {
    if (this.busy()) throw new AppError("game_job_busy", "已有游戏资源任务正在运行", 409);
    const detected = detectGame(path);
    if (kind === "update" && !detected) throw new AppError("game_not_installed", "所选目录中未检测到可更新的原神客户端");
    const build = prepareBuild(await this.provider.getBuild(detected?.version ?? ""), detected?.path ?? "", detected?.version ?? "");
    if (build.kind === "game_hotfix") throw new AppError("game_hotfix_pending", "检测到游戏内热更新清单，请先启动原神完成资源应用", 409);
    const job: GameJob = {
      id: randomUUID(), kind, status: "queued", completed_bytes: 0, total_bytes: size(build), message: "",
      download_speed: 0, chunks_completed: 0, chunks_total: build.assets.reduce((n, value) => n + value.chunks.length, 0),
      active_chunks: [], last_update: "",
    };
    const control = new DownloadControl(); this.jobs.set(job.id, job); this.controls.set(job.id, control);
    void this.run(job, control, detected?.path ?? resolve(path), build);
    return job;
  }

  get(id: string): GameJob {
    const job = this.jobs.get(id);
    if (!job) throw new AppError("game_job_missing", "游戏资源任务不存在", 404);
    return job;
  }

  control(id: string, action: string): GameJob {
    const job = this.get(id);
    const control = this.controls.get(id);
    if (action === "pause" && job.status === "running") { control?.pause(); job.status = "paused"; }
    else if (action === "resume" && job.status === "paused") { control?.resume(); job.status = "running"; }
    else if (action === "cancel" && ["queued", "running", "paused"].includes(job.status)) { control?.cancel(); job.status = "cancelled"; }
    else throw new AppError("game_job_action_invalid", "任务操作与当前状态不匹配", 409);
    return job;
  }

  private async run(job: GameJob, control: DownloadControl, path: string, build: GameBuild): Promise<void> {
    job.status = "running";
    try {
      const cache = join(this.dataDir, "downloads", build.version), staging = `${path}.staging`;
      stageExisting(job.kind === "update" ? path : "", staging); mkdirSync(cache, { recursive: true });
      if (job.kind === "update" && build.kind !== "package_repair") removeRetired(staging, build);
      const progress = (bytes: number): void => { job.completed_bytes += bytes; job.last_update = new Date().toISOString(); };
      const chunk = (name: string, done: number, total: number): void => {
        const value = { name, bytes_done: done, total }; job.active_chunks = [...job.active_chunks.filter((item) => item.name !== name), value].slice(-4);
        job.chunks_completed = Math.max(job.chunks_completed, job.active_chunks.filter((item) => item.bytes_done === item.total).length);
      };
      if (build.patch_assets.length) { await installPatches(build.patch_assets, staging, cache, control, progress, chunk); for (const name of build.deprecated_files) removeSafe(staging, name); }
      else if (build.assets.length) await installSophon(build.assets, staging, cache, control, progress, chunk);
      else {
        const archives: string[] = [];
        for (const segment of build.segments) archives.push(await download(segment, join(cache, segment.filename), control, progress));
        extract(archives, staging); verify(staging);
      }
      if (!existsSync(join(staging, "YuanShen.exe"))) {
        throw new AppError("game_install_incomplete", "资源安装完成后仍缺少 YuanShen.exe，未激活不完整目录");
      }
      writeFileSync(join(staging, ".mhg-version"), build.version);
      if (build.assets.length && build.kind !== "package_repair") writeFileSync(join(staging, ".mhg-assets.json"), JSON.stringify(build.assets.map(({ name }) => name)));
      activate(staging, path); this.saveState(path, build.version);
      job.completed_bytes = job.total_bytes; job.status = "completed";
    } catch (error) {
      job.status = error instanceof DOMException && error.name === "AbortError" ? "cancelled" : "failed";
      job.message = error instanceof Error ? error.message : "游戏任务失败";
    } finally { rmSync(`${path}.staging`, { recursive: true, force: true }); }
  }

  private saveState(path: string, version: string): void {
    this.store.db.prepare(`INSERT INTO game_state(id,install_path,version,status,updated_at) VALUES(1,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET install_path=excluded.install_path,version=excluded.version,status=excluded.status,updated_at=excluded.updated_at`)
      .run(path, version, "ready", new Date().toISOString());
  }
}

function output(path: string, installed: string, build: GameBuild, status: GameState["status"]): GameState {
  return { install_path: path, installed_version: installed, available_version: build.version, status, update_kind: build.kind, download_bytes: size(build) };
}

function size(build: GameBuild): number {
  const patches = new Map(build.patch_assets.map(({ patch }) => [patch.id, patch.file_size]));
  return build.pending_bytes + build.segments.reduce((n, v) => n + v.size, 0)
    + build.assets.flatMap((v) => v.chunks).reduce((n, v) => n + v.size, 0)
    + [...patches.values()].reduce((a, b) => a + b, 0);
}

export function detectGame(input: string): { path: string; version: string } | null {
  for (const path of [resolve(input), join(resolve(input), "Genshin Impact Game")]) {
    if (!existsSync(join(path, "YuanShen.exe"))) continue;
    const marker = join(path, ".mhg-version");
    if (existsSync(marker)) { const version = readFileSync(marker, "utf8").trim(); if (version) return { path, version }; }
    const config = join(path, "config.ini");
    if (!existsSync(config)) continue;
    const version = readFileSync(config, "utf8").match(/^game_version\s*=\s*(.+)$/m)?.[1]?.trim();
    if (version) return { path, version };
  }
  return null;
}
