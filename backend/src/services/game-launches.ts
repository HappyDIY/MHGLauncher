import { randomUUID } from "node:crypto";
import { chmodSync, closeSync, existsSync, fstatSync, mkdirSync, openSync, readFileSync, readSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";
import type { GameLaunch, GamePerformanceProfile } from "../core/models";
import { type DllIntegrity, type DllJournal, MHYPBASE_INTEGRITY, prepareDll, restoreDll } from "./game-launch-files";
import { type GameLaunchRunner, WineLaunchRunner } from "./game-launch-process";
import { recoverInterruptedDlls } from "./game-launch-recovery";
import { ensureGameConfiguration } from "./game-config";
import { detectGame } from "./games";
import type { RegistryAccount } from "./game-account-registry";

export interface StartLaunch {
  install_path: string; performance_profile: GamePerformanceProfile; metal_hud: boolean;
  network_debug: boolean; wine_log: boolean; frame_pacing: number; account?: RegistryAccount; auth_ticket?: string;
}

export class GameLaunchService {
  private readonly launches = new Map<string, GameLaunch>();
  private readonly dnsLines = new Map<string, number>();
  private readonly wineLines = new Map<string, number>();
  private readonly controllers = new Map<string, AbortController>();
  constructor(
    private readonly dataDir: string,
    private readonly runtimeRoot: string,
    private readonly runner: GameLaunchRunner = new WineLaunchRunner(),
    private readonly integrity: DllIntegrity = MHYPBASE_INTEGRITY,
    private readonly resourcesBusy: () => boolean = () => false,
  ) { recoverInterruptedDlls(this.dataDir); }

  start(input: StartLaunch): GameLaunch {
    if (this.resourcesBusy()) throw new AppError("game_job_busy", "游戏资源任务运行期间无法启动游戏", 409);
    if ([...this.launches.values()].some((value) => !["exited", "stopped", "failed"].includes(value.status))) {
      throw new AppError("game_launch_busy", "游戏正在启动或运行", 409);
    }
    const detected = detectGame(input.install_path);
    if (!detected) throw new AppError("game_not_installed", "所选目录中未检测到可启动的原神客户端", 409);
    ensureGameConfiguration(detected.path, detected.version);
    const now = new Date().toISOString();
    const launch: GameLaunch = {
      id: randomUUID(), status: "preparing", message: "", performance_profile: input.performance_profile,
      metal_hud: input.metal_hud, network_debug: input.network_debug, wine_log: input.wine_log, progress: 0.05,
      logs: [{ sequence: 1, timestamp: now, kind: "launch", message: "启动任务已创建" }],
      started_at: now, updated_at: now,
    };
    this.launches.set(launch.id, launch); this.persist(launch);
    const controller = new AbortController(); this.controllers.set(launch.id, controller);
    setImmediate(() => void this.execute(launch, detected.path, input.frame_pacing, controller.signal, input.wine_log, input.account, input.auth_ticket));
    return launch;
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

  private async execute(launch: GameLaunch, gameRoot: string, framePacing: number, signal: AbortSignal, wineLog: boolean, account?: RegistryAccount, authTicket?: string): Promise<void> {
    const sessionDir = join(this.dataDir, "launches", launch.id);
    let journal: DllJournal | null = null;
    try {
      this.update(launch, "preparing", "正在校验并准备游戏文件", 0.1);
      journal = prepareDll(gameRoot, join(this.runtimeRoot, "assets", "mhypbase.dll"), sessionDir, this.integrity);
      this.update(launch, "preparing", "游戏文件准备完成", 0.22);
      const code = await this.runner.run({
        gameRoot, runtimeRoot: this.runtimeRoot, dataDir: this.dataDir, sessionDir,
        profile: launch.performance_profile, metalHud: launch.metal_hud,
        networkDebug: launch.network_debug, wineLog, framePacing, signal, account, authTicket,
      }, (status, message = "", progress) => this.update(launch, status, message, progress));
      const warning = restoreDll(journal);
      const stopped = launch.status === "stopping";
      const status = stopped ? "stopped" : code === 0 ? "exited" : "failed";
      const message = stopped ? "游戏已停止，临时文件已恢复" : code === 0 ? "游戏已正常退出" : `游戏进程退出码：${code}`;
      this.update(launch, status, warning || message, 1);
    } catch (error) {
      const warning = restoreDll(journal);
      const message = error instanceof Error ? error.message : "游戏启动失败";
      this.update(launch, "failed", warning ? `${message}；${warning}` : message);
    } finally {
      this.controllers.delete(launch.id);
      this.dnsLines.delete(launch.id);
      this.wineLines.delete(launch.id);
    }
  }

  private update(launch: GameLaunch, status: GameLaunch["status"], message: string, progress?: number): void {
    const now = new Date().toISOString();
    launch.status = status; launch.message = message; launch.updated_at = now;
    if (progress !== undefined) launch.progress = Math.max(launch.progress, Math.min(progress, 1));
    if (message) launch.logs.push({ sequence: launch.logs.length + 1, timestamp: now, kind: "launch", message });
    this.persist(launch);
  }

  private readDnsLogs(launch: GameLaunch): void {
    const path = join(this.dataDir, "launches", launch.id, "dns.log");
    if (!existsSync(path)) return;
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
    this.dnsLines.set(launch.id, lines.length);
  }

  private readWineLogs(launch: GameLaunch): void {
    const path = join(this.dataDir, "launches", launch.id, "wine.log");
    if (!existsSync(path)) return;
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
    } finally {
      closeSync(fd);
    }
  }

  private persist(launch: GameLaunch): void {
    const directory = join(this.dataDir, "launches", launch.id); mkdirSync(directory, { recursive: true, mode: 0o700 });
    const target = join(directory, "status.json"), temp = `${target}.${process.pid}.tmp`;
    writeFileSync(temp, JSON.stringify(launch), { mode: 0o600 }); chmodSync(temp, 0o600); renameSync(temp, target);
  }
}
