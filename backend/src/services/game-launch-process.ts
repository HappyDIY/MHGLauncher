import { closeSync, existsSync, mkdirSync, openSync, rmSync } from "node:fs";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { AppError } from "../core/errors";
import type { GameLaunchStatus, GamePerformanceProfile } from "../core/models";
import { launchEnvironment, runtimePaths } from "./game-launch-environment";

export interface LaunchRunInput {
  gameRoot: string; runtimeRoot: string; dataDir: string; sessionDir: string;
  profile: GamePerformanceProfile; metalHud: boolean; framePacing: number;
}
export type LaunchReporter = (status: GameLaunchStatus, message?: string) => void;
export interface GameLaunchRunner { run(input: LaunchRunInput, report: LaunchReporter): Promise<number> }

export class WineLaunchRunner implements GameLaunchRunner {
  async run(input: LaunchRunInput, report: LaunchReporter): Promise<number> {
    const paths = runtimePaths(input.runtimeRoot), prefix = join(input.dataDir, "wineprefix");
    this.preflight(paths.wineboot, prefix);
    const env = launchEnvironment(process.env, paths, prefix, input.sessionDir, input.profile, input.metalHud, input.framePacing);
    report("starting");
    const logDir = join(input.dataDir, "logs"); mkdirSync(logDir, { recursive: true, mode: 0o700 });
    const descriptor = openSync(join(logDir, "game-launch.log"), "a", 0o600);
    const child = spawn(paths.wine, [join(input.gameRoot, "YuanShen.exe"), "-force-d3d11"], {
      cwd: input.gameRoot, detached: true, env, stdio: ["ignore", descriptor, descriptor],
    });
    closeSync(descriptor);
    child.unref(); report("waiting_window");
    const gate = String(env.MHG_DNS_GATE_FILE);
    const probe = setInterval(() => {
      if (spawnSync(paths.probe, [String(child.pid ?? 0)], { stdio: "ignore" }).status === 0) {
        rmSync(gate, { force: true }); clearInterval(probe); report("running");
      }
    }, 100);
    return await new Promise<number>((resolve, reject) => {
      child.once("error", (error) => { clearInterval(probe); rmSync(gate, { force: true }); reject(error); });
      child.once("exit", (code) => { clearInterval(probe); rmSync(gate, { force: true }); resolve(code ?? 1); });
    });
  }

  private preflight(wineboot: string, prefix: string): void {
    if (spawnSync("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]).status !== 0) {
      throw new AppError("rosetta_missing", "请先安装 Rosetta 2 后再启动游戏", 409);
    }
    mkdirSync(prefix, { recursive: true, mode: 0o700 });
    if (existsSync(join(prefix, "system.reg"))) return;
    const result = spawnSync(wineboot, ["--init"], {
      env: { ...process.env, WINEPREFIX: prefix, WINEARCH: "win64", WINEDEBUG: "-all" }, stdio: "ignore",
    });
    if (result.status !== 0) throw new AppError("wineprefix_init_failed", "Wine 运行环境初始化失败", 500);
  }
}
