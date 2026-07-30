import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { WineLaunchRunner } from "../src/services/game-launch-process";

const roots: string[] = [];

export function cleanupLaunchFixtures(): void {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
}

export function makeLaunchFixture(): {
  input: Parameters<InstanceType<typeof WineLaunchRunner>["run"]>[0];
  controller: AbortController; dataDir: string; sessionDir: string;
} {
  const root = mkdtempSync(join(tmpdir(), "mhg-launch-run-")); roots.push(root);
  const runtimeRoot = join(root, "runtime"), dataDir = join(root, "data"), gameRoot = join(root, "game"), sessionDir = join(root, "session");
  const files = [
    "wine/bin/wine", "wine/bin/wineboot", "wine/bin/wineserver",
    "wine/lib/wine/x86_64-windows/winemetal.dll", "bin/mhg-window-probe",
    "lib/libmhg_dns_gate.dylib", "assets/mhypbase.dll",
  ];
  for (const file of files) {
    const path = join(runtimeRoot, file);
    mkdirSync(join(path, ".."), { recursive: true });
    writeFileSync(path, "fixture");
  }
  mkdirSync(gameRoot, { recursive: true });
  const controller = new AbortController();
  return {
    controller, dataDir, sessionDir,
    input: {
      gameRoot, runtimeRoot, dataDir, sessionDir, signal: controller.signal,
      profile: "optimized", metalHud: false, networkDebug: false,
      wineLog: false, framePacing: 120,
    },
  };
}
