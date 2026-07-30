import { existsSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";

const spawnSyncMock = vi.fn(() => ({ status: 0, stdout: "" }));
const runCommandMock = vi.fn(async (_command: string, _args: string[], _options?: unknown) => (
  { status: 0, stdout: "", stderr: "" }
));

vi.mock("node:child_process", () => ({
  spawnSync: spawnSyncMock,
  spawn: vi.fn(),
}));
vi.mock("../src/services/process-command", () => ({ runCommand: runCommandMock }));

const { gameArguments } = await import("../src/services/game-launch-process");
const { safeLaunchBase } = await import("../src/services/game-launch-environment");
const { prepareWinePrefix } = await import("../src/services/game-wine-prefix");

const roots: string[] = [];

describe("Wine 游戏进程启动器", () => {
  afterEach(() => {
    spawnSyncMock.mockClear();
    runCommandMock.mockClear();
    for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
  });

  test("预启动时异步启用 Wine Retina 模式", async () => {
    const fixture = makeRuntimeFixture();
    await prepareWinePrefix(fixture.runtimeRoot, fixture.dataDir, "optimized");

    expect(runCommandMock).toHaveBeenCalledWith(fixture.wine, [
      "reg", "add", "HKCU\\Software\\Wine\\Mac Driver",
      "/v", "RetinaMode", "/t", "REG_SZ", "/d", "Y", "/f",
    ], expect.objectContaining({ env: expect.any(Object) }));
    expect(existsSync(join(fixture.prefix, "drive_c", "windows", "system32", "winemetal.dll"))).toBe(true);
  });

  test("Wine 初始化禁止附加组件弹窗并只信任完成标记", async () => {
    const fixture = makeRuntimeFixture();
    mkdirSync(fixture.prefix, { recursive: true });
    writeFileSync(join(fixture.prefix, "system.reg"), "尚未完成");
    await prepareWinePrefix(fixture.runtimeRoot, fixture.dataDir, "optimized");

    expect(runCommandMock).toHaveBeenCalledWith(fixture.wineboot, ["--init"], {
      env: expect.objectContaining({ WINEDLLOVERRIDES: "mscoree,mshtml=" }),
      timeout: 180_000,
    });
    expect(existsSync(join(fixture.prefix, ".mhglauncher-wine-runtime"))).toBe(true);

    runCommandMock.mockClear();
    await prepareWinePrefix(fixture.runtimeRoot, fixture.dataDir, "optimized");
    expect(runCommandMock.mock.calls.some((call) => call[0] === fixture.wineboot)).toBe(false);
  });

  test("Wine 初始化失败时清理残留服务", async () => {
    const fixture = makeRuntimeFixture();
    runCommandMock.mockImplementation(async (command) => command === fixture.wineboot
      ? { status: 1, stdout: "", stderr: "初始化失败" }
      : { status: 0, stdout: "", stderr: "" });
    await expect(prepareWinePrefix(
      fixture.runtimeRoot, fixture.dataDir, "optimized",
    )).rejects.toThrow("Wine 运行环境初始化失败");

    const stopCalls = runCommandMock.mock.calls.filter(([command, args]) => (
      command === fixture.wineserver && args[0] === "-k"
    ));
    expect(stopCalls).toHaveLength(2);
  });

  test("米游社账号使用源项目兼容的登录票据参数", () => {
    expect(gameArguments("-popupwindow \"value with spaces\"", "ticket-value")).toEqual([
      "YuanShen.exe",
      "-force-d3d11",
      "-popupwindow",
      "value with spaces",
      "login_auth_ticket=ticket-value",
    ]);
    expect(gameArguments()).not.toContainEqual(
      expect.stringContaining("login_auth_ticket="),
    );
  });

  test("游戏进程环境不会继承启动器令牌和系统凭据", () => {
    const environment = safeLaunchBase({
      HOME: "/Users/test", PATH: "/usr/bin", TMPDIR: "/tmp",
      MHG_API_TOKEN: "local-secret", SSH_AUTH_SOCK: "/tmp/agent",
      DATABASE_URL: "postgres://secret", OTHER_PASSWORD: "secret",
    });
    expect(environment).toEqual({
      NODE_ENV: "production", HOME: "/Users/test", PATH: "/usr/bin", TMPDIR: "/tmp",
    });
  });
});

function makeRuntimeFixture(): {
  runtimeRoot: string; dataDir: string; wine: string; wineboot: string; wineserver: string;
  winemetal: string; prefix: string;
} {
  const root = mkdtempSync(join(tmpdir(), "mhg-launch-runner-")); roots.push(root);
  const runtimeRoot = join(root, "runtime"), dataDir = join(root, "data"), prefix = join(dataDir, "wineprefix");
  const wine = join(runtimeRoot, "wine/bin/wine"), wineboot = join(runtimeRoot, "wine/bin/wineboot");
  const wineserver = join(runtimeRoot, "wine/bin/wineserver");
  const winemetal = join(runtimeRoot, "wine/lib/wine/x86_64-windows/winemetal.dll");
  for (const path of [
    wine, wineboot, wineserver, winemetal, join(runtimeRoot, "bin/mhg-window-probe"),
    join(runtimeRoot, "lib/libmhg_dns_gate.dylib"), join(runtimeRoot, "assets/mhypbase.dll"),
  ]) {
    mkdirSync(join(path, ".."), { recursive: true }); writeFileSync(path, "fixture");
  }
  return { runtimeRoot, dataDir, wine, wineboot, wineserver, winemetal, prefix };
}
