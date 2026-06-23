import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";
import type { GamePerformanceProfile } from "../core/models";

export interface RuntimePaths {
  wine: string; wineboot: string; wineserver: string; winemetal: string;
  probe: string; dnsGate: string; mhypbase: string;
}

export function runtimePaths(root: string): RuntimePaths {
  const paths = {
    wine: join(root, "wine", "bin", "wine"), wineboot: join(root, "wine", "bin", "wineboot"),
    wineserver: join(root, "wine", "bin", "wineserver"), probe: join(root, "bin", "mhg-window-probe"),
    winemetal: join(root, "wine", "lib", "wine", "x86_64-windows", "winemetal.dll"),
    dnsGate: join(root, "lib", "libmhg_dns_gate.dylib"), mhypbase: join(root, "assets", "mhypbase.dll"),
  };
  for (const path of Object.values(paths)) if (!existsSync(path)) throw new AppError("game_runtime_missing", `内置游戏运行时不完整：${path}`, 500);
  return paths;
}

export function launchEnvironment(
  base: NodeJS.ProcessEnv, paths: RuntimePaths, prefix: string, sessionDir: string,
  profile: GamePerformanceProfile, metalHud: boolean, framePacing: number,
): NodeJS.ProcessEnv {
  const gate = join(sessionDir, "dns-gate");
  mkdirSync(sessionDir, { recursive: true, mode: 0o700 });
  writeFileSync(gate, String(process.pid), { mode: 0o600 });
  const optimized = profile === "optimized", compatibility = profile === "compatibility";
  return {
    ...base, LANG: "zh_CN.UTF-8", LC_ALL: "zh_CN.UTF-8",
    WINEPREFIX: prefix, WINEARCH: "win64", WINEDEBUG: "-all", WINEDLLOVERRIDES: "winedbg.exe=d",
    WINEMSYNC: optimized ? "1" : "0", WINEESYNC: compatibility ? "1" : "0",
    DYLD_INSERT_LIBRARIES: paths.dnsGate, MHG_DNS_GATE_FILE: gate,
    MHG_DNS_GATE_HOSTS: "dispatchcnglobal.yuanshen.com,dispatchosglobal.yuanshen.com",
    MHG_DNS_GATE_OWNER_PID: String(process.pid), MTL_HUD_ENABLED: metalHud ? "1" : "0",
    DXMT_LOG_LEVEL: metalHud ? "info" : "warn", DXMT_LOG_PATH: join(sessionDir, "dxmt"),
    DXMT_SHADER_CACHE_PATH: join(base.HOME ?? "", "Library", "Caches", "MHGLauncher", "dxmt", "YuanShen.exe"),
    DXMT_CONFIG: framePacing > 0 ? `d3d11.preferredMaxFrameRate=${framePacing};` : "",
  };
}
