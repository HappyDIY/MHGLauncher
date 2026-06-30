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
import { ensureGameConfiguration } from "./game-config";
import { writeIntegrityIndex } from "./game-integrity";
import { diskSpaceInfo } from "./disk-space";
import { maybeRateLimiter } from "./rate-limiter";
import { makeProgress } from "./job-progress";
import { downloadChunksOnly, downloadPatchesOnly } from "./predownload"; import { readPredownloadStatus, writePredownloadStatus, clearPredownloadStatus } from "./predownload-status";
import { checkedPredownloadBuild } from "./predownload-build";
import { RevisionNotifier } from "./revision-notifier";
export class GameService {
  private readonly jobs = new Map<string, GameJob>();
  private readonly controls = new Map<string, DownloadControl>();
  private readonly notifier = new RevisionNotifier<GameJob>();
  private mutableSpeedLimitKB = 0;
  constructor(
    private readonly store: Store, private readonly provider: Provider, private readonly dataDir: string,
    private readonly downloadWorkers = 4, downloadSpeedLimitKB = 0,
  ) { this.mutableSpeedLimitKB = downloadSpeedLimitKB; }
  setSpeedLimit(kb: number): void { this.mutableSpeedLimitKB = Math.max(0, kb); }
  getSpeedLimit(): number { return this.mutableSpeedLimitKB; }
  busy(): boolean { return [...this.jobs.values()].some(({ status }) => ["queued", "running", "paused"].includes(status)); }
  async state(requested?: string): Promise<GameState> {
    const stored = this.store.one("SELECT install_path FROM game_state WHERE id=1");
    const candidate = requested || String(stored?.install_path ?? "");
    const detected = candidate ? detectGame(candidate) : null;
    const raw = await this.provider.getBuild(detected?.version ?? "", audioLanguages(detected?.path ?? candidate));
    const build = detected ? prepareBuild(raw, detected.path, detected.version) : raw;
    if (!detected) return output(candidate, "", build, "not_installed");
    this.saveState(detected.path, detected.version);
    const current = detected.version === build.version && !build.assets.length;
    const predownload = await this.predownloadInfo(detected.path);
    return output(detected.path, detected.version, build, current ? "ready" : "update_available", predownload);
  }
  async spaceCheck(path: string, installBytes: number, kind: JobKind = "update"): Promise<{ available: number; required: number; sufficient: boolean }> {
    if (kind !== "predownload") return diskSpaceInfo(path, installBytes);
    const detected = detectGame(path);
    if (!detected) throw new AppError("game_not_installed", "预下载需要已安装的游戏客户端");
    const remote = await this.provider.getPredownloadBuild(audioLanguages(detected.path));
    if (!remote) throw new AppError("predownload_unavailable", "当前没有可用的预下载版本");
    const build = checkedPredownloadBuild(detected.version, await this.provider.getBuild(detected.version, audioLanguages(detected.path)), remote);
    return diskSpaceInfo(detected.path, size(build));
  }
  private async predownloadInfo(gamePath: string): Promise<{ version: string | null; finished: boolean }> {
    try {
      const preBuild = await this.provider.getPredownloadBuild(audioLanguages(gamePath));
      if (!preBuild) return { version: null, finished: false };
      const cache = join(this.dataDir, "downloads", preBuild.version);
      const status = readPredownloadStatus(cache);
      return { version: preBuild.version, finished: status?.finished ?? false };
    } catch { return { version: null, finished: false }; }
  }
  async start(kind: JobKind, path: string): Promise<GameJob> {
    if (this.busy()) throw new AppError("game_job_busy", "已有游戏资源任务正在运行", 409);
    const detected = detectGame(path);
    if (kind === "update" && !detected) throw new AppError("game_not_installed", "所选目录中未检测到可更新的原神客户端");
    if (kind === "predownload" && !detected) throw new AppError("game_not_installed", "预下载需要已安装的游戏客户端");
    const root = detected?.path ?? resolve(path);
    const remote = kind === "predownload" ? await this.provider.getPredownloadBuild(audioLanguages(root)) : null;
    if (kind === "predownload" && !remote) throw new AppError("predownload_unavailable", "当前没有可用的预下载版本");
    const build = kind === "predownload"
      ? checkedPredownloadBuild(detected?.version ?? "", await this.provider.getBuild(detected?.version ?? "", audioLanguages(root)), remote as GameBuild)
      : prepareBuild(await this.provider.getBuild(detected?.version ?? "", audioLanguages(root)), detected?.path ?? "", detected?.version ?? "");
    const spaceInfo = diskSpaceInfo(root, size(build));
    if (!spaceInfo.sufficient) throw new AppError("disk_space_insufficient", `磁盘空间不足：需要 ${spaceInfo.required} 字节，可用 ${spaceInfo.available} 字节`, 422, { available: spaceInfo.available, required: spaceInfo.required, sufficient: spaceInfo.sufficient });
    const job: GameJob = {
      id: randomUUID(), kind, status: "queued", completed_bytes: 0, total_bytes: size(build), message: "",
      download_speed: 0, chunks_completed: 0, chunks_total: build.assets.reduce((n, value) => n + value.chunks.length, 0),
      active_chunks: [], last_update: "", revision: 0,
    };
    const control = new DownloadControl(); this.jobs.set(job.id, this.touch(job)); this.controls.set(job.id, control);
    setImmediate(() => void this.run(job, control, root, build));
    return job;
  }
  get(id: string): GameJob {
    const job = this.jobs.get(id);
    if (!job) throw new AppError("game_job_missing", "游戏资源任务不存在", 404);
    return job;
  }
  async wait(id: string, after: number, waitMs: number): Promise<GameJob> { return this.notifier.wait(id, after, waitMs, () => this.get(id)); }
  control(id: string, action: string): GameJob {
    const job = this.get(id);
    const control = this.controls.get(id);
    if (action === "pause" && job.status === "running") { control?.pause(); job.status = "paused"; this.touch(job); }
    else if (action === "resume" && job.status === "paused") { control?.resume(); job.status = "running"; this.touch(job); }
    else if (action === "cancel" && ["queued", "running", "paused"].includes(job.status)) { control?.cancel(); job.status = "cancelled"; this.touch(job); }
    else throw new AppError("game_job_action_invalid", "任务操作与当前状态不匹配", 409);
    return job;
  }

  private async run(job: GameJob, control: DownloadControl, path: string, build: GameBuild): Promise<void> {
    job.status = "running"; this.touch(job);
    if (job.kind === "predownload") return this.runPredownload(job, control, path, build);
    const inPlace = job.kind !== "install" && build.kind === "package_repair";
    try {
      const cache = join(this.dataDir, "downloads", build.version), staging = inPlace ? path : `${path}.staging`;
      const marker = join(staging, ".mhg-staging-version");
      const resumable = !inPlace && existsSync(marker) && readFileSync(marker, "utf8").trim() === build.version;
      if (!inPlace && !resumable) { stageExisting(job.kind === "update" ? path : "", staging); writeFileSync(marker, build.version); }
      mkdirSync(cache, { recursive: true });
      if (job.kind === "update" && build.kind !== "package_repair") removeRetired(staging, build);
      const limiter = maybeRateLimiter(this.mutableSpeedLimitKB);
      const { progress, chunk, flush } = makeProgress(job, () => this.touch(job));
      if (build.patch_assets.length) { await installPatches(build.patch_assets, staging, cache, control, progress, chunk); for (const name of build.deprecated_files) removeSafe(staging, name); }
      else if (build.assets.length) await installSophon(build.assets, staging, cache, control, progress, chunk, this.downloadWorkers, limiter);
      else {
        const archives: string[] = [];
        for (const segment of build.segments) archives.push(await download(segment, join(cache, segment.filename), control, progress));
        extract(archives, staging); verify(staging);
      }
      if (!existsSync(join(staging, "YuanShen.exe"))) throw new AppError("game_install_incomplete", "资源安装完成后仍缺少 YuanShen.exe，未激活不完整目录");
      if (!inPlace) rmSync(marker, { force: true });
      writeFileSync(join(staging, ".mhg-version"), build.version);
      ensureGameConfiguration(staging, build.version);
      writeIntegrityIndex(staging, build);
      if (build.assets.length && build.kind !== "package_repair") writeFileSync(join(staging, ".mhg-assets.json"), JSON.stringify(build.assets.map(({ name }) => name)));
      if (!inPlace) activate(staging, path);
      this.saveState(path, build.version); rmSync(cache, { recursive: true, force: true }); clearPredownloadStatus(cache);
      flush(); job.completed_bytes = job.total_bytes; job.download_speed = 0; job.status = "completed"; this.touch(job);
    } catch (error) {
      job.download_speed = 0; job.status = error instanceof DOMException && error.name === "AbortError" ? "cancelled" : "failed";
      job.message = error instanceof Error ? error.message : "游戏任务失败"; this.touch(job);
    } finally {
      if (!inPlace && (job.status === "cancelled" || job.status === "completed")) rmSync(`${path}.staging`, { recursive: true, force: true });
    }
  }

  private async runPredownload(job: GameJob, control: DownloadControl, _path: string, build: GameBuild): Promise<void> {
    try {
      const cache = join(this.dataDir, "downloads", build.version);
      mkdirSync(cache, { recursive: true });
      const limiter = maybeRateLimiter(this.mutableSpeedLimitKB);
      const { progress, chunk, flush } = makeProgress(job, () => this.touch(job));
      const totalChunks = build.assets.reduce((n, v) => n + v.chunks.length, 0) + build.patch_assets.length;
      writePredownloadStatus(cache, { tag: build.version, finished: false, total_chunks: totalChunks });
      if (build.patch_assets.length) await downloadPatchesOnly(build.patch_assets, cache, control, progress, chunk, limiter);
      else if (build.assets.length) await downloadChunksOnly(build.assets, cache, control, progress, chunk, this.downloadWorkers, limiter);
      writePredownloadStatus(cache, { tag: build.version, finished: true, total_chunks: totalChunks });
      flush(); job.completed_bytes = job.total_bytes; job.download_speed = 0; job.status = "completed"; this.touch(job);
    } catch (error) {
      job.download_speed = 0; job.status = error instanceof DOMException && error.name === "AbortError" ? "cancelled" : "failed";
      job.message = error instanceof Error ? error.message : "预下载失败"; this.touch(job);
    }
  }

  private touch(job: GameJob): GameJob { job.last_update ||= new Date().toISOString(); return this.notifier.mark(job.id, job); }

  private saveState(path: string, version: string): void {
    this.store.db.prepare(`INSERT INTO game_state(id,install_path,version,status,updated_at) VALUES(1,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET install_path=excluded.install_path,version=excluded.version,status=excluded.status,updated_at=excluded.updated_at`)
      .run(path, version, "ready", new Date().toISOString());
  }
}

function output(path: string, installed: string, build: GameBuild, status: GameState["status"], predownload?: { version: string | null; finished: boolean }): GameState {
  return { install_path: path, installed_version: installed, available_version: build.version, status, update_kind: build.kind, download_bytes: size(build), predownload_version: predownload?.version ?? null, predownload_finished: predownload?.finished ?? false };
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

function audioLanguages(path: string): string[] {
  const files: Record<string, string> = {
    "zh-cn": "Audio_Chinese_pkg_version", "en-us": "Audio_English(US)_pkg_version",
    "ja-jp": "Audio_Japanese_pkg_version", "ko-kr": "Audio_Korean_pkg_version",
  };
  const selected = Object.entries(files).filter(([, name]) => existsSync(join(path, name))).map(([language]) => language);
  return selected.length ? selected : ["zh-cn"];
}
