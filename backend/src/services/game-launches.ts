import { randomUUID } from "node:crypto";
import { closeSync, existsSync, fstatSync, openSync, readFileSync, readSync } from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";
import type { GameLaunch, GamePerformanceProfile } from "../core/models";
import { type DllIntegrity, type DllJournal, MHYPBASE_INTEGRITY, prepareDll, restoreDll } from "./game-launch-files";
import { type GameLaunchRunner, WineLaunchRunner } from "./game-launch-process";
import { DllRecoveryGuardian } from "./game-launch-guardian";
import { ensureGameConfiguration } from "./game-config";
import { detectGame } from "./game-detection";
import type { RegistryAccount } from "./game-account-registry";
import { RevisionNotifier } from "./revision-notifier";
import { loadLaunchStatuses, persistLaunchStatus } from "./game-launch-status-store";
import { ResourceCoordinator, type ResourceLease } from "./resource-coordinator";
export interface StartLaunch {
  install_path: string; performance_profile: GamePerformanceProfile; metal_hud: boolean;
  network_debug: boolean; wine_log: boolean; frame_pacing: number; account?: RegistryAccount;
}
export class GameLaunchService {
  private readonly launches = new Map<string, GameLaunch>();
  private readonly dnsLines = new Map<string, number>();
  private readonly wineLines = new Map<string, number>();
  private readonly logReadAt = new Map<string, number>();
  private readonly controllers = new Map<string, AbortController>();
  private readonly notifier = new RevisionNotifier<GameLaunch>();
  private readonly persisted = new Map<string, string>();
  private readonly guardian: DllRecoveryGuardian;
  constructor(
    private readonly dataDir: string,
    private readonly runtimeRoot: string,
    private readonly runner: GameLaunchRunner = new WineLaunchRunner(),
    private readonly integrity: DllIntegrity = MHYPBASE_INTEGRITY,
    private readonly coordinator = new ResourceCoordinator(),
  ) {
    for (const launch of loadLaunchStatuses(this.dataDir)) {
      this.launches.set(launch.id, launch); this.persisted.set(launch.id, JSON.stringify(launch)); this.notifier.mark(launch.id, launch);
    }
    this.guardian = new DllRecoveryGuardian(this.dataDir, () => this.finishRecovered());
    if (!this.guardian.pending()) this.finishRecovered();
  }
  start(input: StartLaunch): GameLaunch {
    if ([...this.launches.values()].some((value) => !["exited", "stopped", "failed"].includes(value.status))) {
      throw new AppError("game_launch_busy", "游戏正在启动或运行", 409);
    }
    const detected = detectGame(input.install_path);
    if (!detected) throw new AppError("game_not_installed", "所选目录中未检测到可启动的原神客户端", 409);
    const id = randomUUID(), lease = this.coordinator.claim(detected.path, id);
    try {
    ensureGameConfiguration(detected.path, detected.version);
    const now = new Date().toISOString();
    const launch: GameLaunch = {
      id, status: "preparing", message: "", performance_profile: input.performance_profile,
      metal_hud: input.metal_hud, network_debug: input.network_debug, wine_log: input.wine_log, progress: 0.05,
      logs: [{ sequence: 1, timestamp: now, kind: "launch", message: "启动任务已创建" }],
      started_at: now, updated_at: now, revision: 0,
    };
    this.notifier.mark(launch.id, launch); this.persist(launch); this.launches.set(launch.id, launch);
    const controller = new AbortController(); this.controllers.set(launch.id, controller);
    setImmediate(() => void this.execute(launch, detected.path, input.frame_pacing, controller.signal, input.wine_log, lease, input.account));
    return launch;
    } catch (error) { this.coordinator.release(lease); throw error; }
  }
  async wait(id: string, after: number, waitMs: number): Promise<GameLaunch> {
    return this.notifier.wait(id, after, waitMs, () => this.get(id));
  }
  get(id: string): GameLaunch {
    const launch = this.launches.get(id);
    if (!launch) throw new AppError("game_launch_missing", "游戏启动会话不存在", 404);
    if (launch.network_debug) this.readDnsLogs(launch);
    if (launch.wine_log) this.readWineLogs(launch);
    return launch;
  }
  stop(id: string): GameLaunch {
    const launch = this.get(id);
    if (["exited", "stopped", "failed"].includes(launch.status)) return launch;
    this.update(launch, "stopping", "正在安全停止游戏并恢复临时文件");
    this.controllers.get(id)?.abort();
    return launch;
  }
  active(): boolean { return [...this.launches.values()].some((value) => !["exited", "stopped", "failed"].includes(value.status)); }
  recovery(): { pending: boolean; warnings: string[] } { return { pending: this.guardian.pending(), warnings: this.guardian.warnings() }; }
  async drain(): Promise<void> { await this.guardian.drain(() => this.active()); }
  close(): void { this.guardian.close(); }
  private async execute(launch: GameLaunch, gameRoot: string, framePacing: number, signal: AbortSignal, wineLog: boolean, lease: ResourceLease, account?: RegistryAccount): Promise<void> {
    const sessionDir = join(this.dataDir, "launches", launch.id);
    let journal: DllJournal | null = null, code: number | null = null, failure: unknown = null;
    try {
      this.update(launch, "preparing", "正在校验并准备游戏文件", 0.1);
      journal = prepareDll(gameRoot, join(this.runtimeRoot, "assets", "mhypbase.dll"), sessionDir, this.integrity);
      this.update(launch, "preparing", "游戏文件准备完成", 0.22);
      code = await this.runner.run({
        gameRoot, runtimeRoot: this.runtimeRoot, dataDir: this.dataDir, sessionDir,
        profile: launch.performance_profile, metalHud: launch.metal_hud,
        networkDebug: launch.network_debug, wineLog, framePacing, signal, account,
      }, (status, message = "", progress) => this.update(launch, status, message, progress));
    } catch (error) {
      failure = error;
    } finally {
      try {
      let warning = "", pending = false;
      if (failure instanceof AppError && failure.code === "wine_server_stop_failed") {
        warning = "Wine 进程尚未确认退出，DLL 恢复记录已交由守护任务"; pending = true;
      } else {
        try { const result = restoreDll(journal); warning = result.warning; pending = result.pending; }
        catch (error) { warning = error instanceof Error ? error.message : "DLL 恢复失败"; pending = true; }
      }
      if (pending || failure) this.guardian.refresh();
      if (failure) {
        const message = failure instanceof AppError ? failure.message : "游戏启动失败，请稍后重试";
        this.update(launch, "failed", warning ? `${message}；${warning}` : message);
      } else {
        const stopped = launch.status === "stopping", status = stopped ? "stopped" : code === 0 ? "exited" : "failed";
        const message = stopped ? "游戏已停止，临时文件已恢复" : code === 0 ? "游戏已正常退出" : `游戏进程退出码：${code}`;
        this.update(launch, status, warning || message, 1);
      }
      } catch (error) {
        launch.status = "failed"; launch.message = error instanceof Error ? error.message : "启动会话终态持久化失败";
        this.notifier.mark(launch.id, launch); this.guardian.refresh();
      } finally {
      this.controllers.delete(launch.id);
      this.dnsLines.delete(launch.id);
      this.wineLines.delete(launch.id);
      this.logReadAt.delete(launch.id);
      this.coordinator.release(lease);
      }
    }
  }
  private update(launch: GameLaunch, status: GameLaunch["status"], message: string, progress?: number): void {
    const now = new Date().toISOString();
    launch.status = status; launch.message = message; launch.updated_at = now;
    if (progress !== undefined) launch.progress = Math.max(launch.progress, Math.min(progress, 1));
    if (message) launch.logs.push({ sequence: launch.logs.length + 1, timestamp: now, kind: "launch", message });
    this.notifier.mark(launch.id, launch); this.persist(launch);
  }
  private readDnsLogs(launch: GameLaunch): void {
    const path = join(this.dataDir, "launches", launch.id, "dns.log");
    if (!existsSync(path)) return;
    if (!this.canReadLogs(`${launch.id}:dns`)) return;
    const lines = readFileSync(path, "utf8").split("\n").filter(Boolean);
    const offset = this.dnsLines.get(launch.id) ?? 0;
    for (const line of lines.slice(offset)) {
      const [milliseconds, pid, api, host, action, result, address] = line.split("\t");
      if (!milliseconds || !pid || !api || !host || !action || result === undefined) continue;
      const state = action === "blocked" ? "屏蔽" : Number(result) === 0 ? `成功${address ? ` → ${address}` : ""}` : `未找到 ${result}`;
      launch.logs.push({
        sequence: launch.logs.length + 1, timestamp: new Date(Number(milliseconds)).toISOString(), kind: "dns",
        message: `DNS · PID ${pid} · ${api} · ${host} · ${state}`,
      });
    }
    if (lines.length !== offset) { this.dnsLines.set(launch.id, lines.length); this.notifier.mark(launch.id, launch); this.persist(launch); }
  }

  private readWineLogs(launch: GameLaunch): void {
    const path = join(this.dataDir, "launches", launch.id, "wine.log");
    if (!existsSync(path)) return;
    if (!this.canReadLogs(`${launch.id}:wine`)) return;
    const fd = openSync(path, "r");
    try {
      const size = fstatSync(fd).size;
      const offset = this.wineLines.get(launch.id) ?? 0;
      if (offset >= size) return;
      const length = Math.min(size - offset, 256 * 1024);
      const buffer = Buffer.alloc(length);
      readSync(fd, buffer, 0, length, offset);
      this.wineLines.set(launch.id, offset + length);
      const now = new Date().toISOString();
      const lines = buffer.toString("utf8").split("\n").filter(Boolean);
      const recent = lines.slice(-30);
      for (const line of recent) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        launch.logs.push({
          sequence: launch.logs.length + 1, timestamp: now, kind: "wine",
          message: trimmed.slice(0, 500),
        });
      }
      const limit = 200;
      if (launch.logs.length > limit) launch.logs = launch.logs.slice(-limit);
      if (recent.length) { this.notifier.mark(launch.id, launch); this.persist(launch); }
    } finally {
      closeSync(fd);
    }
  }

  private persist(launch: GameLaunch): void {
    const payload = JSON.stringify(launch);
    if (this.persisted.get(launch.id) === payload) return;
    this.persisted.set(launch.id, persistLaunchStatus(this.dataDir, launch));
  }
  private finishRecovered(): void {
    for (const launch of this.launches.values()) if (!["exited", "stopped", "failed"].includes(launch.status)) {
      this.update(launch, "exited", this.guardian.warnings().at(-1) ?? "游戏已退出，临时文件已由恢复守护任务还原", 1);
    }
  }
  private canReadLogs(id: string): boolean {
    const now = Date.now(), previous = this.logReadAt.get(id) ?? 0;
    if (now - previous < 1_000) return false;
    this.logReadAt.set(id, now); return true;
  }
}
