import { closeSync, copyFileSync, existsSync, mkdirSync, openSync, rmSync } from "node:fs";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { AppError } from "../core/errors";
import type { GameLaunchStatus, GamePerformanceProfile } from "../core/models";
import { launchEnvironment, runtimePaths } from "./game-launch-environment";
import { configureChineseGameLanguage } from "./game-launch-language";
import { writeGameAccountRegistry, type RegistryAccount } from "./game-account-registry";

export interface LaunchRunInput {
  gameRoot: string; runtimeRoot: string; dataDir: string; sessionDir: string;
  profile: GamePerformanceProfile; metalHud: boolean; networkDebug: boolean; framePacing: number; signal: AbortSignal;
  account?: RegistryAccount;
}
export type LaunchReporter = (status: GameLaunchStatus, message?: string, progress?: number) => void;
export interface GameLaunchRunner { run(input: LaunchRunInput, report: LaunchReporter): Promise<number> }

export class WineLaunchRunner implements GameLaunchRunner {
  async run(input: LaunchRunInput, report: LaunchReporter): Promise<number> {
    const paths = runtimePaths(input.runtimeRoot), prefix = join(input.dataDir, "wineprefix");
    if (input.signal.aborted) return 0;
    report("preparing", "正在初始化 Wine 容器", 0.3);
    this.preflight(paths.wine, paths.wineboot, paths.wineserver, paths.winemetal, prefix, input.profile);
    if (input.signal.aborted) return 0;
    report("starting", "Wine 容器已切换为简体中文", 0.55);
    const env = launchEnvironment(
      process.env, paths, prefix, input.sessionDir, input.profile,
      input.metalHud, input.networkDebug, input.framePacing,
    );
    if (input.account) {
      writeGameAccountRegistry(paths.wine, env, input.account);
      report("starting", "已将启动器账号写入游戏登录状态", 0.62);
    }
    report("starting", "正在创建游戏进程", 0.68);
    const snapshot = spawnSync(paths.probe, ["--snapshot"], { encoding: "utf8" }).stdout
      .trim().split("\n").filter(Boolean).join(",");
    const logDir = join(input.dataDir, "logs"); mkdirSync(logDir, { recursive: true, mode: 0o700 });
    const descriptor = openSync(join(logDir, "game-launch.log"), "a", 0o600);
    const child = spawn(paths.wine, [join(input.gameRoot, "YuanShen.exe"), "-force-d3d11"], {
      cwd: input.gameRoot, detached: true, env, stdio: ["ignore", descriptor, descriptor],
    });
    closeSync(descriptor);
    child.unref(); report("waiting_window", "游戏进程已创建，正在等待窗口", 0.82);
    const gate = String(env.MHG_DNS_GATE_FILE);
    let released = false;
    const releaseGate = (message: string): void => {
      if (released) return;
      released = true; rmSync(gate, { force: true }); report("running", message, 1);
    };
    const probe = setInterval(() => {
      if (spawnSync(paths.probe, [String(child.pid ?? 0), snapshot], { stdio: "ignore" }).status === 0) {
        clearInterval(probe); releaseGate("游戏窗口已显示，域名屏蔽已解除");
      }
    }, 25);
    const fallback = setTimeout(() => {
      clearInterval(probe); releaseGate("窗口探针超时，已自动解除域名屏蔽");
    }, 30_000);
    return await new Promise<number>((resolve, reject) => {
      const cleanup = (): void => { clearInterval(probe); clearTimeout(fallback); rmSync(gate, { force: true }); };
      const stop = (): void => { cleanup(); this.stopServer(paths.wineserver, prefix); resolve(0); };
      input.signal.addEventListener("abort", stop, { once: true });
      child.once("error", (error) => { cleanup(); input.signal.removeEventListener("abort", stop); this.stopServer(paths.wineserver, prefix); reject(error); });
      child.once("exit", (code) => { cleanup(); input.signal.removeEventListener("abort", stop); this.stopServer(paths.wineserver, prefix); resolve(code ?? 1); });
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
      ...process.env, LANG: "zh_CN.UTF-8", LANGUAGE: "zh_CN:zh",
      LC_ALL: "zh_CN.UTF-8", LC_MESSAGES: "zh_CN.UTF-8",
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
    configureChineseGameLanguage(wine, localeEnv);
    this.stopServer(wineserver, prefix);
    const system32 = join(prefix, "drive_c", "windows", "system32"); mkdirSync(system32, { recursive: true });
    copyFileSync(winemetal, join(system32, "winemetal.dll"));
  }

  private configureChineseLocale(wine: string, env: NodeJS.ProcessEnv): void {
    const values: Array<[string, string, string, string]> = [
      ["HKCU\\Control Panel\\International", "LocaleName", "REG_SZ", "zh-CN"],
      ["HKCU\\Control Panel\\International", "Locale", "REG_SZ", "00000804"],
      ["HKCU\\Control Panel\\Desktop", "PreferredUILanguages", "REG_MULTI_SZ", "zh-CN"],
      ["HKCU\\Control Panel\\International\\User Profile", "Languages", "REG_MULTI_SZ", "zh-Hans-CN"],
      ["HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "Default", "REG_SZ", "0804"],
      ["HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language", "InstallLanguage", "REG_SZ", "0804"],
      ["HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "ACP", "REG_SZ", "936"],
      ["HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage", "OEMCP", "REG_SZ", "936"],
    ];
    for (const [key, name, type, value] of values) {
      const result = spawnSync(wine, ["reg", "add", key, "/v", name, "/t", type, "/d", value, "/f"], {
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
