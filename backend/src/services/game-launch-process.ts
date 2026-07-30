import { closeSync, mkdirSync, openSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawn } from "node:child_process";
import { parseArgsStringToArgv } from "string-argv";
import type { GameLaunchStatus, GamePerformanceProfile } from "../core/models";
import { launchEnvironment } from "./game-launch-environment";
import { createGameLaunchLink, removeGameLaunchLink } from "./game-launch-link";
import { runCommand } from "./process-command";
import { stopWineServer } from "./game-wine-server";
import { prepareWinePrefix } from "./game-wine-prefix";

export interface LaunchRunInput {
  gameRoot: string; runtimeRoot: string; dataDir: string; sessionDir: string;
  profile: GamePerformanceProfile; metalHud: boolean; networkDebug: boolean; wineLog: boolean;
  framePacing: number; signal: AbortSignal;
  authTicket?: string; launchArguments?: string;
}
export type LaunchReporter = (status: GameLaunchStatus, message?: string, progress?: number) => void;
export interface GameLaunchRunner { run(input: LaunchRunInput, report: LaunchReporter): Promise<number> }
export interface LaunchProbeTiming { intervalMs: number; timeoutMs: number }

export class WineLaunchRunner implements GameLaunchRunner {
  constructor(private readonly probeTiming: LaunchProbeTiming = { intervalMs: 250, timeoutMs: 30_000 }) {}

  async run(input: LaunchRunInput, report: LaunchReporter): Promise<number> {
    if (input.signal.aborted) return 0;
    report("preparing", "正在初始化 Wine 容器", 0.3);
    const { paths, prefix } = await prepareWinePrefix(input.runtimeRoot, input.dataDir, input.profile);
    if (input.signal.aborted) return 0;
    report("starting", "Wine 容器已切换为简体中文", 0.55);
    const env = launchEnvironment(
      process.env, paths, prefix, input.sessionDir, input.profile,
      input.metalHud, input.networkDebug, input.wineLog, input.framePacing,
    );
    if (input.authTicket) report("starting", "已准备米游社账号登录票据", 0.62);
    report("starting", "正在创建游戏进程", 0.68);
    const snapshot = (await runCommand(paths.probe, ["--snapshot"], { timeout: 1_000 })).stdout
      .trim().split("\n").filter(Boolean).join(",");
    const logPath = input.wineLog
      ? join(input.sessionDir, "wine.log")
      : join(input.dataDir, "logs", "game-launch.log");
    mkdirSync(dirname(logPath), { recursive: true, mode: 0o700 });
    const gameLink = createGameLaunchLink(input.gameRoot, input.sessionDir);
    let descriptor: number;
    try { descriptor = openSync(logPath, "a", 0o600); }
    catch (error) { removeGameLaunchLink(gameLink); throw error; }
    const exeArgs = gameArguments(input.launchArguments, input.authTicket);
    let child: ReturnType<typeof spawn>;
    try {
      child = spawn(paths.wine, exeArgs, {
        cwd: gameLink, detached: true, env, stdio: ["ignore", descriptor, descriptor],
      });
    } catch (error) {
      removeGameLaunchLink(gameLink);
      throw error;
    } finally {
      closeSync(descriptor);
    }
    const gate = String(env.MHG_DNS_GATE_FILE);
    let released = false;
    const releaseGate = (message: string): void => {
      if (released) return;
      released = true; rmSync(gate, { force: true }); report("running", message, 1);
    };
    let probing = false, processReported = false;
    const probe = setInterval(() => {
      if (probing) return; probing = true;
      void runCommand(paths.probe, [String(child.pid ?? 0), snapshot], { timeout: 1_000 })
        .then((result) => {
          if (result.status === 0) {
            clearInterval(probe); releaseGate("游戏窗口已显示，域名屏蔽已解除");
          } else if (result.status === 3 && !processReported) {
            processReported = true;
            report("running", "游戏进程已创建，正在等待窗口", 0.9);
          }
        })
        .finally(() => { probing = false; });
    }, this.probeTiming.intervalMs);
    const fallback = setTimeout(() => {
      clearInterval(probe); releaseGate("窗口探针超时，已自动解除域名屏蔽");
    }, this.probeTiming.timeoutMs);
    let terminate: (() => void) | undefined;
    const completion = new Promise<number>((resolve, reject) => {
      let cleaned = false, reported = false, finishing = false;
      const cleanup = (): void => { clearInterval(probe); clearTimeout(fallback); rmSync(gate, { force: true }); };
      const finish = async (code: number, error?: unknown): Promise<void> => {
        if (cleaned || finishing) return; finishing = true; cleanup();
        try {
          try { await stopWineServer(paths.wineserver, prefix); }
          finally { removeGameLaunchLink(gameLink); }
          cleaned = true;
          if (!reported) { reported = true; if (error) reject(error); else resolve(code); }
        } catch (stopError) { if (!reported) { reported = true; reject(stopError); } }
      };
      const stop = (): void => { void finish(0); };
      terminate = stop;
      input.signal.addEventListener("abort", stop, { once: true });
      child.once("error", (error) => { input.signal.removeEventListener("abort", stop); void finish(1, error); });
      child.once("exit", (code) => { input.signal.removeEventListener("abort", stop); void finish(code ?? 1); });
    });
    try { report("waiting_window", "游戏进程已创建，正在等待窗口", 0.82); }
    catch (error) {
      terminate?.();
      try { await completion; } catch { /* 保留报告器错误。 */ }
      throw error;
    }
    return await completion;
  }

}

export function gameArguments(custom = "", authTicket?: string): string[] {
  const args = ["YuanShen.exe", "-force-d3d11", ...parseArgsStringToArgv(custom)];
  if (authTicket) args.push(`login_auth_ticket=${authTicket}`);
  return args;
}
