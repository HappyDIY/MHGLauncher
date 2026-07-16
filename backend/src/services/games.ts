import { existsSync, mkdirSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { createHash, randomUUID } from "node:crypto";
import { AppError } from "../core/errors";
import type { GameJob, GameState, JobKind } from "../core/models";
import type { Store } from "../core/database";
import type { GameBuild, Provider } from "../providers/provider";
import { DownloadControl } from "./download";
import { activate, stageExisting } from "./installer";
import { operationChunks, prepareBuild } from "./game-build";
import { ensureGameConfiguration } from "./game-config";
import { writeIntegrityIndex } from "./game-integrity";
import { diskSpaceInfo } from "./disk-space";
import { maybeRateLimiter } from "./rate-limiter";
import { makeProgress } from "./job-progress";
import { downloadChunksOnly, downloadPatchesOnly } from "./predownload"; import { predownloadCachedBytes, predownloadDigest, readPredownloadStatus, writePredownloadStatus, clearPredownloadStatus } from "./predownload-status";
import { checkedPredownloadBuild, compareGameVersions } from "./predownload-build";
import { RevisionNotifier } from "./revision-notifier";
import { audioLanguages, detectGame, gameBuildSize as size, gameStateOutput as output, gameStorageSize } from "./game-detection";
import { ResourceCoordinator, type ResourceLease } from "./resource-coordinator";
import { pruneTerminal } from "./task-retention";
import { installGameResources } from "./game-resource-install";
import { managedPath, writeManagedFile } from "./managed-file";
import { makeGameResourceProgress } from "./game-resource-progress";
import { findInstallResume, gameOperationPaths, type GameOperationPaths } from "./game-install-resume";
import { localStorageError } from "./storage-error";
export class GameService {
  private readonly jobs = new Map<string, GameJob>();
  private readonly controls = new Map<string, DownloadControl>();
  private readonly notifier = new RevisionNotifier<GameJob>();
  private mutableSpeedLimitKB = 0;
  constructor(private readonly store: Store, private readonly provider: Provider, private readonly dataDir: string,
    private readonly downloadWorkers = 4, downloadSpeedLimitKB = 0, private readonly coordinator = new ResourceCoordinator()) { this.mutableSpeedLimitKB = downloadSpeedLimitKB; }
  setSpeedLimit(kb: number): void { this.mutableSpeedLimitKB = Math.max(0, kb); }
  getSpeedLimit(): number { return this.mutableSpeedLimitKB; }
  busy(): boolean { return [...this.jobs.values()].some(({ status }) => ["queued", "running", "pausing", "paused", "cancelling"].includes(status)); }
  async state(requested?: string): Promise<GameState> {
    const stored = this.store.one("SELECT install_path FROM game_state WHERE id=1");
    const input = requested || String(stored?.install_path ?? ""), detected = input ? detectGame(input) : null;
    const resume = input && !detected ? findInstallResume(input) : null;
    const candidate = detected?.path ?? resume?.destination ?? input, source = detected?.path ?? resume?.source ?? "";
    const version = detected?.version ?? resume?.version ?? "";
    const raw = await this.provider.getBuild(version, audioLanguages(source || candidate));
    const build = source ? prepareBuild(raw, source, version) : raw;
    if (!detected) return output(candidate, resume?.version ?? "", build, resume ? "damaged" : "not_installed");
    this.saveState(detected.path, detected.version);
    const current = compareGameVersions(detected.version, build.version) >= 0;
    const predownload = await this.predownloadInfo(detected.path);
    return output(detected.path, detected.version, build, current ? "ready" : "update_available", predownload);
  }
  async spaceCheck(path: string, _installBytes: number, kind: JobKind = "update"): Promise<{ available: number; required: number; sufficient: boolean }> {
    const paths = gameOperationPaths(kind, path), { detected } = paths;
    if (kind !== "install" && !detected) throw new AppError("game_not_installed", "资源操作需要已安装的游戏客户端");
    if (kind !== "predownload") {
      const root = paths.root;
      const source = kind === "verify" && detected ? await this.provider.getInstalledBuild(detected.version, audioLanguages(root))
        : await this.provider.getBuild(paths.version, audioLanguages(paths.source || root));
      const build = prepareBuild(source, paths.source, paths.version);
      const cached = await predownloadCachedBytes(this.cacheFor(root, build.version), build);
      return diskSpaceInfo(root, gameStorageSize(build) - cached);
    }
    if (!detected) throw new AppError("game_not_installed", "预下载需要已安装的游戏客户端");
    const remote = await this.provider.getPredownloadBuild(detected.version, audioLanguages(detected.path));
    if (!remote) throw new AppError("predownload_unavailable", "当前没有可用的预下载版本");
    const build = checkedPredownloadBuild(detected.version, await this.provider.getInstalledBuild(detected.version, audioLanguages(detected.path)), remote);
    const cached = await predownloadCachedBytes(this.cacheFor(detected.path, build.version), build);
    return diskSpaceInfo(detected.path, gameStorageSize(build, true) - cached);
  }
  private async predownloadInfo(gamePath: string): Promise<{ version: string | null; finished: boolean }> {
    try {
      const current = detectGame(gamePath)?.version ?? "";
      const preBuild = await this.provider.getPredownloadBuild(current, audioLanguages(gamePath));
      if (!preBuild) return { version: null, finished: false };
      const local = await this.provider.getInstalledBuild(current, audioLanguages(gamePath));
      const checked = checkedPredownloadBuild(current, local, preBuild);
      const cache = this.cacheFor(gamePath, preBuild.version);
      const status = await readPredownloadStatus(cache, checked, false);
      return { version: preBuild.version, finished: status?.finished ?? false };
    } catch { return { version: null, finished: false }; }
  }
  async start(kind: JobKind, path: string): Promise<GameJob> {
    for (const id of pruneTerminal(this.jobs, ({ status }) => ["completed", "cancelled", "failed"].includes(status), ({ last_update }) => Date.parse(last_update) || 0)) this.controls.delete(id);
    if (this.busy()) throw new AppError("game_job_busy", "已有游戏资源任务正在运行", 409);
    const paths = gameOperationPaths(kind, path), { detected } = paths;
    if (kind === "update" && !detected) throw new AppError("game_not_installed", "所选目录中未检测到可更新的原神客户端");
    if (kind === "predownload" && !detected) throw new AppError("game_not_installed", "预下载需要已安装的游戏客户端");
    const root = paths.root;
    const jobId = randomUUID(), lease = this.coordinator.claim(root, jobId);
    try {
    const remote = kind === "predownload" ? await this.provider.getPredownloadBuild(detected?.version ?? "", audioLanguages(root)) : null;
    if (kind === "predownload" && !remote) throw new AppError("predownload_unavailable", "当前没有可用的预下载版本");
    const build = kind === "predownload"
      ? checkedPredownloadBuild(detected?.version ?? "", await this.provider.getInstalledBuild(detected?.version ?? "", audioLanguages(root)), remote as GameBuild)
      : prepareBuild(kind === "verify" && detected
        ? await this.provider.getInstalledBuild(detected.version, audioLanguages(root))
        : await this.provider.getBuild(paths.version, audioLanguages(paths.source || root)),
      paths.source, paths.version);
    const cache = this.cacheFor(root, build.version), cached = await predownloadCachedBytes(cache, build);
    const spaceInfo = diskSpaceInfo(root, gameStorageSize(build, kind === "predownload") - cached);
    if (!spaceInfo.sufficient) throw new AppError("disk_space_insufficient", `磁盘空间不足：需要 ${spaceInfo.required} 字节，可用 ${spaceInfo.available} 字节`, 422, { available: spaceInfo.available, required: spaceInfo.required, sufficient: spaceInfo.sufficient });
    if (kind === "update" && detected && compareGameVersions(detected.version, build.version) >= 0) throw new AppError("game_already_current", "当前游戏版本已是最新", 409);
    const hasWork = build.assets.length > 0 || build.patch_assets.length > 0 || build.segments.length > 0 || build.deprecated_files.length > 0;
    if (kind !== "predownload" && detected?.version !== build.version && !hasWork && !paths.resume) {
      throw new AppError("game_build_empty", "下载服务返回了不完整的空构建", 502);
    }
    const job: GameJob = {
      id: jobId, kind, status: "queued", completed_bytes: 0, total_bytes: size(build), message: kind === "predownload" ? "预下载任务已排队" : kind === "verify" ? "校验任务已排队" : kind === "install" ? "安装任务已排队" : "更新任务已排队",
      download_speed: 0, chunks_completed: 0, chunks_total: new Set([...build.assets.flatMap(operationChunks).map(({ name }) => name), ...build.patch_assets.map(({ patch }) => patch.id)]).size,
      active_chunks: [], last_update: "", revision: 0,
    };
    const control = new DownloadControl(); this.jobs.set(job.id, this.touch(job)); this.controls.set(job.id, control);
    setImmediate(() => void this.run(job, control, paths, build, lease));
    return job;
    } catch (error) { this.coordinator.release(lease); throw error; }
  }
  get(id: string): GameJob {
    const job = this.jobs.get(id);
    if (!job) throw new AppError("game_job_missing", "游戏资源任务不存在", 404);
    return job;
  }
  async wait(id: string, after: number, waitMs: number, signal?: AbortSignal): Promise<GameJob> { return this.notifier.wait(id, after, waitMs, () => this.get(id), signal); }
  control(id: string, action: string): GameJob {
    const job = this.get(id);
    const control = this.controls.get(id);
    if (action === "pause" && job.status === "running" && control) {
      const acknowledged = control.pause(); job.status = "pausing"; this.touch(job);
      void acknowledged.then(() => { if (job.status === "pausing") { job.status = "paused"; this.touch(job); } });
    }
    else if (action === "resume" && job.status === "paused") { control?.resume(); job.status = "running"; this.touch(job); }
    else if (action === "cancel" && ["queued", "running", "pausing", "paused"].includes(job.status)) { control?.cancel(); job.status = "cancelling"; this.touch(job); }
    else if (action === "cancel" && ["completed", "cancelled", "failed"].includes(job.status)) return job;
    else throw new AppError("game_job_action_invalid", "任务操作与当前状态不匹配", 409);
    return job;
  }
  private async run(job: GameJob, control: DownloadControl, paths: GameOperationPaths, build: GameBuild, lease: ResourceLease): Promise<void> {
    const path = paths.root;
    job.status = "running"; job.message = job.kind === "predownload" ? "正在下载预下载资源" : job.kind === "verify" ? "正在校验游戏资源" : job.kind === "install" ? "正在安装游戏资源" : "正在更新游戏资源"; this.touch(job);
    if (job.kind === "predownload") return this.runPredownload(job, control, path, build, lease);
    const resume = job.kind === "install" ? paths.resume : null, inPlaceResume = resume?.source === path;
    const inPlaceVerify = job.kind === "verify";
    const staging = inPlaceVerify ? path : resume?.source ?? `${path}.mhg-staging-${job.id}`;
    try {
      const cache = this.cacheFor(path, build.version);
      await control.checkpoint();
      if (!resume && !inPlaceVerify) { stageExisting(job.kind === "install" ? paths.source : path, staging); writeManagedFile(staging, ".mhg-staging-version", build.version); }
      mkdirSync(cache, { recursive: true });
      const limiter = maybeRateLimiter(this.mutableSpeedLimitKB);
      const reporting = makeGameResourceProgress(job, build, () => this.touch(job));
      const canonical = await installGameResources({
        build, kind: job.kind, staging, cache, control, progress: reporting.progress, chunk: reporting.chunk,
        workers: this.downloadWorkers, limiter, reserve: reporting.reserve, phase: reporting.phase,
      });
      await control.checkpoint(); job.message = "正在提交游戏目录"; job.download_speed = 0; this.touch(job);
      if (!existsSync(managedPath(staging, "YuanShen.exe"))) throw new AppError("game_install_incomplete", "资源安装完成后仍缺少 YuanShen.exe，未激活不完整目录");
      writeManagedFile(staging, ".mhg-version", build.version);
      ensureGameConfiguration(staging, build.version);
      writeIntegrityIndex(staging, canonical);
      if (canonical.assets.length) writeManagedFile(staging, ".mhg-assets.json", JSON.stringify(canonical.assets.map(({ name }) => name)));
      if (!inPlaceResume && !inPlaceVerify) activate(staging, path);
      rmSync(managedPath(path, ".mhg-staging-version"), { force: true });
      if (paths.resume && paths.resume.source !== path) rmSync(paths.resume.source, { recursive: true, force: true });
      this.saveState(path, build.version); rmSync(job.kind === "verify" ? cache : this.cacheScopeFor(path), { recursive: true, force: true }); clearPredownloadStatus(cache);
      reporting.flush(); job.completed_bytes = job.total_bytes; job.download_speed = 0; job.status = "completed";
      job.message = job.kind === "install" ? "游戏资源安装完成" : job.kind === "verify" ? "游戏资源校验完成" : "游戏资源更新完成"; this.touch(job);
    } catch (error) {
      const failure = localStorageError(error);
      job.download_speed = 0; job.status = error instanceof DOMException && error.name === "AbortError" ? "cancelled" : "failed";
      job.message = failure instanceof AppError ? failure.message : "游戏任务失败，请稍后重试"; this.touch(job);
    } finally { if (!resume && !inPlaceVerify && (job.kind !== "install" || !existsSync(join(staging, ".mhg-staging-version")))) rmSync(staging, { recursive: true, force: true }); this.coordinator.release(lease); }
  }
  private async runPredownload(job: GameJob, control: DownloadControl, path: string, build: GameBuild, lease: ResourceLease): Promise<void> {
    try {
      const cache = this.cacheFor(path, build.version);
      mkdirSync(cache, { recursive: true });
      const limiter = maybeRateLimiter(this.mutableSpeedLimitKB);
      const { progress, chunk, flush } = makeProgress(job, () => this.touch(job));
      const totalChunks = new Set([...build.assets.flatMap(operationChunks).map(({ name }) => name), ...build.patch_assets.map(({ patch }) => patch.id)]).size;
      if (totalChunks === 0) throw new AppError("predownload_build_empty", "预下载构建不包含可缓存资源", 502);
      const manifestDigest = predownloadDigest(build);
      writePredownloadStatus(cache, { tag: build.version, manifest_digest: manifestDigest, finished: false, total_chunks: totalChunks });
      if (build.patch_assets.length) await downloadPatchesOnly(build.patch_assets, cache, control, progress, chunk, limiter);
      else if (build.assets.length) await downloadChunksOnly(build.assets, cache, control, progress, chunk, this.downloadWorkers, limiter);
      await control.checkpoint();
      writePredownloadStatus(cache, { tag: build.version, manifest_digest: manifestDigest, finished: true, total_chunks: totalChunks });
      flush(); job.completed_bytes = job.total_bytes; job.download_speed = 0; job.status = "completed"; this.touch(job);
    } catch (error) {
      job.download_speed = 0; job.status = error instanceof DOMException && error.name === "AbortError" ? "cancelled" : "failed";
      job.message = error instanceof AppError ? error.message : "预下载失败，请稍后重试"; this.touch(job);
    } finally { this.coordinator.release(lease); }
  }
  private touch(job: GameJob): GameJob { job.last_update ||= new Date().toISOString(); return this.notifier.mark(job.id, job); }
  private saveState(path: string, version: string): void {
    this.store.db.prepare(`INSERT INTO game_state(id,install_path,version,status,updated_at) VALUES(1,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET install_path=excluded.install_path,version=excluded.version,status=excluded.status,updated_at=excluded.updated_at`)
      .run(path, version, "ready", new Date().toISOString());
  }
  private cacheScopeFor(path: string): string { return join(this.dataDir, "downloads", createHash("sha256").update(resolve(path)).digest("hex").slice(0, 16)); }
  private cacheFor(path: string, version: string): string { return join(this.cacheScopeFor(path), version); }
}
