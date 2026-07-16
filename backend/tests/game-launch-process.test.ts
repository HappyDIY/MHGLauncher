import { existsSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";

const spawnSyncMock = vi.fn(() => ({ status: 0, stdout: "" }));
const runCommandMock = vi.fn(async () => ({ status: 0, stdout: "", stderr: "" }));

vi.mock("node:child_process", () => ({
  spawnSync: spawnSyncMock,
  spawn: vi.fn(),
}));
vi.mock("../src/services/process-command", () => ({ runCommand: runCommandMock }));

const { WineLaunchRunner, gameArguments } = await import("../src/services/game-launch-process");

const roots: string[] = [];

describe("Wine 游戏进程启动器", () => {
  afterEach(() => {
    spawnSyncMock.mockClear();
    runCommandMock.mockClear();
    for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
  });

  test("预启动时异步启用 Wine Retina 模式", async () => {
    const fixture = makeRuntimeFixture();
    const runner = new WineLaunchRunner() as unknown as {
      preflight: (
        wine: string,
        wineboot: string,
        wineserver: string,
        winemetal: string,
        prefix: string,
        profile: "optimized",
      ) => Promise<void>;
    };

    await runner.preflight(
      fixture.wine,
      fixture.wineboot,
      fixture.wineserver,
      fixture.winemetal,
      fixture.prefix,
      "optimized",
    );

    expect(runCommandMock).toHaveBeenCalledWith(fixture.wine, [
      "reg", "add", "HKCU\\Software\\Wine\\Mac Driver",
      "/v", "RetinaMode", "/t", "REG_SZ", "/d", "Y", "/f",
    ], expect.objectContaining({ env: expect.any(Object) }));
    expect(existsSync(join(fixture.prefix, "drive_c", "windows", "system32", "winemetal.dll"))).toBe(true);
  });

  test("米游社账号使用源项目兼容的登录票据参数", () => {
    expect(gameArguments("/games/Genshin Impact Game", "ticket-value")).toEqual([
      "/games/Genshin Impact Game/YuanShen.exe",
      "-force-d3d11",
      "login_auth_ticket=ticket-value",
    ]);
    expect(gameArguments("/games/Genshin Impact Game")).not.toContainEqual(
      expect.stringContaining("login_auth_ticket="),
    );
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
