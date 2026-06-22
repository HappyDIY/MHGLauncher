import { randomUUID } from "node:crypto";
import { chmodSync, mkdirSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";
import type { GameLaunch, GamePerformanceProfile } from "../core/models";
import { type DllIntegrity, type DllJournal, MHYPBASE_INTEGRITY, prepareDll, restoreDll } from "./game-launch-files";
import { type GameLaunchRunner, WineLaunchRunner } from "./game-launch-process";
import { detectGame } from "./games";

export interface StartLaunch {
  install_path: string; performance_profile: GamePerformanceProfile; metal_hud: boolean; frame_pacing: number;
}

export class GameLaunchService {
  private readonly launches = new Map<string, GameLaunch>();
  constructor(
    private readonly dataDir: string,
    private readonly runtimeRoot: string,
    private readonly runner: GameLaunchRunner = new WineLaunchRunner(),
    private readonly integrity: DllIntegrity = MHYPBASE_INTEGRITY,
    private readonly resourcesBusy: () => boolean = () => false,
  ) {}

  start(input: StartLaunch): GameLaunch {
    if (this.resourcesBusy()) throw new AppError("game_job_busy", "游戏资源任务运行期间无法启动游戏", 409);
    if ([...this.launches.values()].some((value) => !["exited", "failed"].includes(value.status))) {
      throw new AppError("game_launch_busy", "游戏正在启动或运行", 409);
    }
    const detected = detectGame(input.install_path);
    if (!detected) throw new AppError("game_not_installed", "所选目录中未检测到可启动的原神客户端", 409);
    const now = new Date().toISOString();
    const launch: GameLaunch = {
      id: randomUUID(), status: "preparing", message: "", performance_profile: input.performance_profile,
      metal_hud: input.metal_hud, started_at: now, updated_at: now,
    };
    this.launches.set(launch.id, launch); this.persist(launch);
    void this.execute(launch, detected.path, input.frame_pacing);
    return launch;
  }

  get(id: string): GameLaunch {
    const launch = this.launches.get(id);
    if (!launch) throw new AppError("game_launch_missing", "游戏启动会话不存在", 404);
    return launch;
  }

  private async execute(launch: GameLaunch, gameRoot: string, framePacing: number): Promise<void> {
    const sessionDir = join(this.dataDir, "launches", launch.id);
    let journal: DllJournal | null = null;
    try {
      journal = prepareDll(gameRoot, join(this.runtimeRoot, "assets", "mhypbase.dll"), sessionDir, this.integrity);
      const code = await this.runner.run({
        gameRoot, runtimeRoot: this.runtimeRoot, dataDir: this.dataDir, sessionDir,
        profile: launch.performance_profile, metalHud: launch.metal_hud, framePacing,
      }, (status, message = "") => this.update(launch, status, message));
      const warning = restoreDll(journal);
      this.update(launch, code === 0 ? "exited" : "failed", warning || (code === 0 ? "" : `游戏进程退出码：${code}`));
    } catch (error) {
      const warning = restoreDll(journal);
      const message = error instanceof Error ? error.message : "游戏启动失败";
      this.update(launch, "failed", warning ? `${message}；${warning}` : message);
    }
  }

  private update(launch: GameLaunch, status: GameLaunch["status"], message: string): void {
    launch.status = status; launch.message = message; launch.updated_at = new Date().toISOString(); this.persist(launch);
  }

  private persist(launch: GameLaunch): void {
    const directory = join(this.dataDir, "launches", launch.id); mkdirSync(directory, { recursive: true, mode: 0o700 });
    const target = join(directory, "status.json"), temp = `${target}.${process.pid}.tmp`;
    writeFileSync(temp, JSON.stringify(launch), { mode: 0o600 }); chmodSync(temp, 0o600); renameSync(temp, target);
  }
}
