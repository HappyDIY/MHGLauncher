import {
  copyFileSync, mkdirSync, readFileSync, renameSync, writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { AppError } from "../core/errors";
import type { GamePerformanceProfile } from "../core/models";
import { runtimePaths, safeLaunchBase, type RuntimePaths } from "./game-launch-environment";
import { configureChineseGameLanguage } from "./game-launch-language";
import { runCommand } from "./process-command";
import { stopWineServer } from "./game-wine-server";

export interface PreparedWinePrefix { paths: RuntimePaths; prefix: string }

export async function prepareWinePrefix(
  runtimeRoot: string, dataDir: string, profile: GamePerformanceProfile, configure = true,
): Promise<PreparedWinePrefix> {
  const paths = runtimePaths(runtimeRoot), prefix = join(dataDir, "wineprefix");
  if (!configure && winePrefixReady(prefix, paths.wine)) return { paths, prefix };
  if (spawnSync("/usr/bin/arch", ["-x86_64", "/usr/bin/true"], { timeout: 5_000 }).status !== 0) {
    throw new AppError("rosetta_missing", "请先安装 Rosetta 2 后再启动 Wine", 409);
  }
  mkdirSync(prefix, { recursive: true, mode: 0o700 });
  await stopWineServer(paths.wineserver, prefix);
  const env = { ...prefixEnvironment(process.env, prefix, profile), WINEDLLOVERRIDES: "mscoree,mshtml=" };
  if (!winePrefixReady(prefix, paths.wine)) {
    const result = await runCommand(paths.wineboot, ["--init"], { env, timeout: 180_000 });
    if (result.status !== 0) {
      try { await stopWineServer(paths.wineserver, prefix); } catch { /* 保留原始初始化错误。 */ }
      throw new AppError("wineprefix_init_failed", "Wine 运行环境初始化失败", 500);
    }
    markWinePrefixReady(prefix, paths.wine);
  }
  await configureChineseLocale(paths.wine, env);
  await configureRetinaMode(paths.wine, env);
  await configureChineseGameLanguage(paths.wine, env);
  await stopWineServer(paths.wineserver, prefix);
  const system32 = join(prefix, "drive_c", "windows", "system32"); mkdirSync(system32, { recursive: true });
  copyFileSync(paths.winemetal, join(system32, "winemetal.dll"));
  return { paths, prefix };
}

export function prefixEnvironment(
  base: NodeJS.ProcessEnv, prefix: string, profile: GamePerformanceProfile,
): NodeJS.ProcessEnv {
  return {
    ...safeLaunchBase(base), LANG: "zh_CN.UTF-8", LANGUAGE: "zh_CN:zh",
    LC_ALL: "zh_CN.UTF-8", LC_MESSAGES: "zh_CN.UTF-8",
    WINEPREFIX: prefix, WINEARCH: "win64", WINEDEBUG: "-all",
    WINEDLLOVERRIDES: "winedbg.exe=d",
    WINEMSYNC: profile === "optimized" ? "1" : "0", WINEESYNC: profile === "compatibility" ? "1" : "0",
  };
}

async function configureChineseLocale(wine: string, env: NodeJS.ProcessEnv): Promise<void> {
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
    const result = await runCommand(wine, ["reg", "add", key, "/v", name, "/t", type, "/d", value, "/f"], { env });
    if (result.status !== 0) throw new AppError("wine_locale_failed", "Wine 中文环境配置失败", 500);
  }
}

async function configureRetinaMode(wine: string, env: NodeJS.ProcessEnv): Promise<void> {
  const result = await runCommand(wine, [
    "reg", "add", "HKCU\\Software\\Wine\\Mac Driver",
    "/v", "RetinaMode", "/t", "REG_SZ", "/d", "Y", "/f",
  ], { env });
  if (result.status !== 0) throw new AppError("wine_retina_failed", "Wine 高分辨率模式配置失败", 500);
}

const prefixReadyFile = ".mhglauncher-wine-runtime";
function winePrefixReady(prefix: string, wine: string): boolean {
  try { return readFileSync(join(prefix, prefixReadyFile), "utf8") === wineRuntimeIdentity(wine); }
  catch { return false; }
}
function markWinePrefixReady(prefix: string, wine: string): void {
  const marker = join(prefix, prefixReadyFile), temporary = `${marker}.tmp`;
  writeFileSync(temporary, wineRuntimeIdentity(wine), { mode: 0o600 }); renameSync(temporary, marker);
}
function wineRuntimeIdentity(wine: string): string {
  try { return `${wine}\n${readFileSync(join(dirname(dirname(wine)), "BUILD_PROVENANCE.json"), "utf8")}`; }
  catch { return `${wine}\n`; }
}
