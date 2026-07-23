import { EventEmitter } from "node:events";
import {
  existsSync, mkdtempSync, mkdirSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  spawn: vi.fn(),
  spawnSync: vi.fn(() => ({ status: 0, stdout: "" })),
  runCommand: vi.fn(async () => ({ status: 0, stdout: "", stderr: "" })),
}));

vi.mock("node:child_process", () => ({
  spawn: mocks.spawn,
  spawnSync: mocks.spawnSync,
}));
vi.mock("../src/services/process-command", () => ({ runCommand: mocks.runCommand }));

const { WineLaunchRunner } = await import("../src/services/game-launch-process");

class FakeChild extends EventEmitter {
  pid = 42;
}

const roots: string[] = [];
let child: FakeChild;

describe("WineLaunchRunner.run", () => {
  beforeEach(() => {
    child = new FakeChild();
    mocks.spawn.mockReset().mockReturnValue(child);
    mocks.spawnSync.mockClear();
    mocks.runCommand.mockReset().mockResolvedValue({ status: 0, stdout: "", stderr: "" });
  });

  afterEach(() => {
    vi.useRealTimers();
    for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
  });

  test("正常退出会等待 Wine Server 并清理域名门禁", async () => {
    const fixture = makeFixture();
    const report = vi.fn();
    const completion = new WineLaunchRunner().run(fixture.input, report);
    await spawned();

    child.emit("exit", 0);

    await expect(completion).resolves.toBe(0);
    expect(report).toHaveBeenCalledWith("waiting_window", expect.any(String), 0.82);
    expect(existsSync(join(fixture.sessionDir, "dns-gate"))).toBe(false);
    expect(statSync(join(fixture.dataDir, "logs", "game-launch.log")).mode & 0o777).toBe(0o600);
  });

  test("spawn 失败会关闭日志并返回原始错误", async () => {
    const fixture = makeFixture();
    const failure = new Error("spawn failed");
    mocks.spawn.mockImplementationOnce(() => { throw failure; });

    await expect(new WineLaunchRunner().run(fixture.input, vi.fn())).rejects.toBe(failure);
    expect(statSync(join(fixture.dataDir, "logs", "game-launch.log")).mode & 0o777).toBe(0o600);
  });

  test("子进程错误会清理并拒绝", async () => {
    const fixture = makeFixture();
    const failure = new Error("child error");
    const completion = new WineLaunchRunner().run(fixture.input, vi.fn());
    await spawned();

    child.emit("error", failure);

    await expect(completion).rejects.toBe(failure);
    expect(existsSync(join(fixture.sessionDir, "dns-gate"))).toBe(false);
  });

  test("取消会进入终态并完成清理", async () => {
    const fixture = makeFixture();
    const completion = new WineLaunchRunner().run(fixture.input, vi.fn());
    await spawned();

    fixture.controller.abort();

    await expect(completion).resolves.toBe(0);
    expect(existsSync(join(fixture.sessionDir, "dns-gate"))).toBe(false);
  });

  test("窗口探针成功会提前释放门禁", async () => {
    const fixture = makeFixture();
    const report = vi.fn();
    const completion = new WineLaunchRunner().run(fixture.input, report);
    await spawned();

    await vi.waitFor(() => {
      expect(report).toHaveBeenCalledWith("running", "游戏窗口已显示，域名屏蔽已解除", 1);
    });
    expect(existsSync(join(fixture.sessionDir, "dns-gate"))).toBe(false);
    child.emit("exit", 0);
    await completion;
  });

  test("窗口探针超时仍会释放门禁", async () => {
    const fixture = makeFixture();
    const report = vi.fn();
    mocks.runCommand.mockImplementation(async (...args: unknown[]) => {
      const command = Array.isArray(args[1]) ? args[1] : [];
      const isWindowProbe = String(args[0]).endsWith("mhg-window-probe")
        && command[0] !== "--snapshot";
      return { status: isWindowProbe ? 1 : 0, stdout: "", stderr: "" };
    });
    const completion = new WineLaunchRunner({ intervalMs: 5, timeoutMs: 20 })
      .run(fixture.input, report);
    await spawned();

    await vi.waitFor(() => {
      expect(report).toHaveBeenCalledWith("running", "窗口探针超时，已自动解除域名屏蔽", 1);
    });

    child.emit("exit", 0);
    await completion;
  });

  test("Wine Server 停止失败会拒绝而不是伪装成功", async () => {
    const fixture = makeFixture();
    const completion = new WineLaunchRunner().run(fixture.input, vi.fn());
    await spawned();
    mocks.runCommand.mockImplementation(async (...args: unknown[]) => (
      String(args[0]).endsWith("wineserver")
        ? { status: 2, stdout: "", stderr: "failed" }
        : { status: 0, stdout: "", stderr: "" }
    ));

    child.emit("exit", 0);

    await expect(completion).rejects.toMatchObject({ code: "wine_server_stop_failed" });
    expect(existsSync(join(fixture.sessionDir, "dns-gate"))).toBe(false);
  });
});

async function spawned(): Promise<void> {
  await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
}

function makeFixture(): {
  input: Parameters<InstanceType<typeof WineLaunchRunner>["run"]>[0];
  controller: AbortController; dataDir: string; sessionDir: string;
} {
  const root = mkdtempSync(join(tmpdir(), "mhg-launch-run-")); roots.push(root);
  const runtimeRoot = join(root, "runtime"), dataDir = join(root, "data");
  const gameRoot = join(root, "game"), sessionDir = join(root, "session");
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
