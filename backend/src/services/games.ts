import { existsSync, readFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { AppError } from "../core/errors";
import type { GameJob, GameState, JobKind } from "../core/models";
import type { Store } from "../core/database";
import type { GameBuild, Provider } from "../providers/provider";

export class GameService {
  private readonly jobs = new Map<string, GameJob>();
  constructor(private readonly store: Store, private readonly provider: Provider) {}

  async state(requested?: string): Promise<GameState> {
    const stored = this.store.one("SELECT install_path FROM game_state WHERE id=1");
    const candidate = requested || String(stored?.install_path ?? "");
    const detected = candidate ? detect(candidate) : null;
    const build = await this.provider.getBuild(detected?.version ?? "");
    if (!detected) return output(candidate, "", build, "not_installed");
    this.saveState(detected.path, detected.version);
    const current = detected.version === build.version && !build.assets.length;
    return output(detected.path, detected.version, build, current ? "ready" : "update_available");
  }

  async start(kind: JobKind, path: string): Promise<GameJob> {
    if ([...this.jobs.values()].some(({ status }) => status === "queued" || status === "running")) throw new AppError("game_job_busy", "已有游戏资源任务正在运行", 409);
    const detected = detect(path);
    if (kind === "update" && !detected) throw new AppError("game_not_installed", "所选目录中未检测到可更新的原神客户端");
    const build = await this.provider.getBuild(detected?.version ?? "");
    const job: GameJob = {
      id: randomUUID(), kind, status: "queued", completed_bytes: 0, total_bytes: size(build), message: "",
      download_speed: 0, chunks_completed: 0, chunks_total: build.assets.reduce((n, value) => n + value.chunks.length, 0),
      active_chunks: [], last_update: "",
    };
    this.jobs.set(job.id, job);
    void this.run(job, detected?.path ?? resolve(path), build);
    return job;
  }

  get(id: string): GameJob {
    const job = this.jobs.get(id);
    if (!job) throw new AppError("game_job_missing", "游戏资源任务不存在", 404);
    return job;
  }

  control(id: string, action: string): GameJob {
    const job = this.get(id);
    if (action === "pause" && job.status === "running") job.status = "paused";
    else if (action === "resume" && job.status === "paused") job.status = "running";
    else if (action === "cancel" && ["queued", "running", "paused"].includes(job.status)) job.status = "cancelled";
    else throw new AppError("game_job_action_invalid", "任务操作与当前状态不匹配", 409);
    return job;
  }

  private async run(job: GameJob, _path: string, build: GameBuild): Promise<void> {
    job.status = "running";
    try {
      if (size(build) > 0) throw new AppError("game_backend_pending", "游戏资源安装器迁移尚未完成", 501);
      job.completed_bytes = job.total_bytes; job.status = "completed";
    } catch (error) { job.status = "failed"; job.message = error instanceof Error ? error.message : "游戏任务失败"; }
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

function detect(input: string): { path: string; version: string } | null {
  for (const path of [resolve(input), join(resolve(input), "Genshin Impact Game")]) {
    const marker = join(path, ".mhg-version");
    if (existsSync(marker)) { const version = readFileSync(marker, "utf8").trim(); if (version) return { path, version }; }
    const config = join(path, "config.ini");
    if (!existsSync(join(path, "YuanShen.exe")) || !existsSync(config)) continue;
    const version = readFileSync(config, "utf8").match(/^game_version\s*=\s*(.+)$/m)?.[1]?.trim();
    if (version) return { path, version };
  }
  return null;
}

export const safeName = (path: string): string => basename(path);
