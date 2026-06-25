import { existsSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";

const spawnSyncMock = vi.fn(() => ({ status: 0, stdout: "" }));

vi.mock("node:child_process", () => ({
  spawnSync: spawnSyncMock,
  spawn: vi.fn(),
}));

const { WineLaunchRunner } = await import("../src/services/game-launch-process");

const roots: string[] = [];

describe("Wine 游戏进程启动器", () => {
  afterEach(() => {
    spawnSyncMock.mockClear();
    for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
  });

  test("预启动时启用 Wine Retina 模式", () => {
    const fixture = makeRuntimeFixture();
    const runner = new WineLaunchRunner() as unknown as {
      preflight: (
        wine: string,
        wineboot: string,
        wineserver: string,
        winemetal: string,
        prefix: string,
        profile: "optimized",
      ) => void;
    };

    runner.preflight(
      fixture.wine,
      fixture.wineboot,
      fixture.wineserver,
      fixture.winemetal,
      fixture.prefix,
      "optimized",
    );

    expect(spawnSyncMock).toHaveBeenCalledWith(fixture.wine, [
      "reg", "add", "HKCU\\Software\\Wine\\Mac Driver",
      "/v", "RetinaMode", "/t", "REG_SZ", "/d", "Y", "/f",
    ], expect.objectContaining({ stdio: "ignore" }));
    expect(existsSync(join(fixture.prefix, "drive_c", "windows", "system32", "winemetal.dll"))).toBe(true);
  });
});

function makeRuntimeFixture(): {
  wine: string; wineboot: string; wineserver: string; winemetal: string; prefix: string;
} {
  const root = mkdtempSync(join(tmpdir(), "mhg-launch-runner-")); roots.push(root);
  const runtime = join(root, "runtime"), prefix = join(root, "prefix");
  const wine = join(runtime, "wine"), wineboot = join(runtime, "wineboot");
  const wineserver = join(runtime, "wineserver"), winemetal = join(runtime, "winemetal.dll");
  mkdirSync(runtime, { recursive: true }); writeFileSync(winemetal, "fixture");
  return { wine, wineboot, wineserver, winemetal, prefix };
}
