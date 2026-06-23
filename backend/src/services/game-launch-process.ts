import { closeSync, copyFileSync, existsSync, mkdirSync, openSync, rmSync } from "node:fs";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { AppError } from "../core/errors";
import type { GameLaunchStatus, GamePerformanceProfile } from "../core/models";
import { launchEnvironment, runtimePaths } from "./game-launch-environment";

export interface LaunchRunInput {
  gameRoot: string; runtimeRoot: string; dataDir: string; sessionDir: string;
  profile: GamePerformanceProfile; metalHud: boolean; framePacing: number;
}
export type LaunchReporter = (status: GameLaunchStatus, message?: string, progress?: number) => void;
export interface GameLaunchRunner { run(input: LaunchRunInput, report: LaunchReporter): Promise<number> }

export class WineLaunchRunner implements GameLaunchRunner {
  async run(input: LaunchRunInput, report: LaunchReporter): Promise<number> {
    const paths = runtimePaths(input.runtimeRoot), prefix = join(input.dataDir, "wineprefix");
    report("preparing", "正在初始化 Wine 容器", 0.3);
    this.preflight(paths.wine, paths.wineboot, paths.wineserver, paths.winemetal, prefix, input.profile);
    report("starting", "Wine 容器已切换为简体中文", 0.55);
    const env = launchEnvironment(process.env, paths, prefix, input.sessionDir, input.profile, input.metalHud, input.framePacing);
    report("starting", "正在创建游戏进程", 0.68);
    const logDir = join(input.dataDir, "logs"); mkdirSync(logDir, { recursive: true, mode: 0o700 });
    const descriptor = openSync(join(logDir, "game-launch.log"), "a", 0o600);
    const child = spawn(paths.wine, [join(input.gameRoot, "YuanShen.exe"), "-force-d3d11"], {
      cwd: input.gameRoot, detached: true, env, stdio: ["ignore", descriptor, descriptor],
    });
    closeSync(descriptor);
    child.unref(); report("waiting_window", "游戏进程已创建，正在等待窗口", 0.82);
    const gate = String(env.MHG_DNS_GATE_FILE);
    const probe = setInterval(() => {
      if (spawnSync(paths.probe, [String(child.pid ?? 0)], { stdio: "ignore" }).status === 0) {
        rmSync(gate, { force: true }); clearInterval(probe);
        report("running", "游戏窗口已显示，域名屏蔽已解除", 1);
      }
    }, 25);
    return await new Promise<number>((resolve, reject) => {
      child.once("error", (error) => { clearInterval(probe); rmSync(gate, { force: true }); this.stopServer(paths.wineserver, prefix); reject(error); });
      child.once("exit", (code) => { clearInterval(probe); rmSync(gate, { force: true }); this.stopServer(paths.wineserver, prefix); resolve(code ?? 1); });
    });
  }

  private preflight(
    wine: string, wineboot: string, wineserver: string, winemetal: string,
    prefix: string, profile: GamePerformanceProfile,
  ): void {
    if (spawnSync("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]).status !== 0) {
      throw new AppError("rosetta_missing", "请先安装 Rosetta 2 后再启动游戏", 409);
    }
    mkdirSync(prefix, { recursive: true, mode: 0o700 });
    this.stopServer(wineserver, prefix);
    const localeEnv = {
      ...process.env, LANG: "zh_CN.UTF-8", LC_ALL: "zh_CN.UTF-8",
      WINEPREFIX: prefix, WINEARCH: "win64", WINEDEBUG: "-all",
      WINEMSYNC: profile === "optimized" ? "1" : "0", WINEESYNC: profile === "compatibility" ? "1" : "0",
    };
    if (!existsSync(join(prefix, "system.reg"))) {
      const result = spawnSync(wineboot, ["--init"], {
        env: localeEnv,
        stdio: "ignore",
      });
      if (result.status !== 0) throw new AppError("wineprefix_init_failed", "Wine 运行环境初始化失败", 500);
    }
    this.configureChineseLocale(wine, localeEnv);
    this.stopServer(wineserver, prefix);
    const system32 = join(prefix, "drive_c", "windows", "system32"); mkdirSync(system32, { recursive: true });
    copyFileSync(winemetal, join(system32, "winemetal.dll"));
  }

  private configureChineseLocale(wine: string, env: NodeJS.ProcessEnv): void {
    const values: Array<[string, string, string]> = [
      ["HKCU\\Control Panel\\International", "LocaleName", "zh-CN"],
      ["HKCU\\Control Panel\\International", "Locale", "00000804"],
      ["HKCU\\Control Panel\\Desktop", "PreferredUILanguages", "zh-CN"],
    ];
    for (const [key, name, value] of values) {
      const result = spawnSync(wine, ["reg", "add", key, "/v", name, "/t", "REG_SZ", "/d", value, "/f"], {
        env, stdio: "ignore",
      });
      if (result.status !== 0) throw new AppError("wine_locale_failed", "Wine 中文环境配置失败", 500);
    }
  }

  private stopServer(wineserver: string, prefix: string): void {
    const env = { ...process.env, WINEPREFIX: prefix, WINEDEBUG: "-all" };
    spawnSync(wineserver, ["-k"], { env, stdio: "ignore" });
    spawnSync(wineserver, ["-w"], { env, stdio: "ignore" });
  }
}
