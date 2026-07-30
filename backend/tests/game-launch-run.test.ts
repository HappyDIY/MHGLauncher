import { EventEmitter } from "node:events";
import { existsSync, lstatSync, mkdirSync, realpathSync, statSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { cleanupLaunchFixtures, makeLaunchFixture as makeFixture } from "./game-launch-run-fixture";

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
    cleanupLaunchFixtures();
  });

  test("正常退出会等待 Wine Server 并清理域名门禁", async () => {
    const fixture = makeFixture(), report = vi.fn();
    const completion = new WineLaunchRunner().run(fixture.input, report);
    await spawned();

    const args = mocks.spawn.mock.calls[0]?.[1] as string[], options = mocks.spawn.mock.calls[0]?.[2] as { cwd: string };
    expect(args[0]).toBe("YuanShen.exe"); expect(lstatSync(options.cwd).isSymbolicLink()).toBe(true);
    expect(realpathSync(options.cwd)).toBe(realpathSync(fixture.input.gameRoot));
    child.emit("exit", 0);

    await expect(completion).resolves.toBe(0);
    expect(report).toHaveBeenCalledWith("waiting_window", expect.any(String), 0.82);
    expect(existsSync(join(fixture.sessionDir, "dns-gate"))).toBe(false);
    expect(existsSync(join(fixture.sessionDir, "game"))).toBe(false);
    expect(statSync(join(fixture.dataDir, "logs", "game-launch.log")).mode & 0o777).toBe(0o600);
  });

  test("spawn 失败会关闭日志并返回原始错误", async () => {
    const fixture = makeFixture(), failure = new Error("spawn failed");
    mocks.spawn.mockImplementationOnce(() => { throw failure; });

    await expect(new WineLaunchRunner().run(fixture.input, vi.fn())).rejects.toBe(failure);
    expect(existsSync(join(fixture.sessionDir, "game"))).toBe(false);
    expect(statSync(join(fixture.dataDir, "logs", "game-launch.log")).mode & 0o777).toBe(0o600);
  });

  test("日志打开失败会清理启动软链接", async () => {
    const fixture = makeFixture(); mkdirSync(join(fixture.dataDir, "logs", "game-launch.log"), { recursive: true });
    await expect(new WineLaunchRunner().run(fixture.input, vi.fn())).rejects.toMatchObject({ code: "EISDIR" });
    expect(existsSync(join(fixture.sessionDir, "game"))).toBe(false);
  });

  test("状态报告器失败会停止会话并清理软链接", async () => {
    const fixture = makeFixture(), failure = new Error("report failed");
    const report = vi.fn((status: string) => {
      if (status === "waiting_window") throw failure;
    });
    await expect(new WineLaunchRunner().run(fixture.input, report)).rejects.toBe(failure);
    expect(existsSync(join(fixture.sessionDir, "game"))).toBe(false);
  });

  test("子进程错误会清理并拒绝", async () => {
    const fixture = makeFixture(), failure = new Error("child error");
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

  test("发现游戏进程时保留一次性域名门控", async () => {
    const fixture = makeFixture();
    const report = vi.fn();
    mocks.runCommand.mockImplementation(async (...args: unknown[]) => {
      const command = Array.isArray(args[1]) ? args[1] : [];
      const isProbe = String(args[0]).endsWith("mhg-window-probe")
        && command[0] !== "--snapshot";
      return { status: isProbe ? 3 : 0, stdout: "", stderr: "" };
    });
    const completion = new WineLaunchRunner({ intervalMs: 5, timeoutMs: 1_000 })
      .run(fixture.input, report);
    await spawned();

    await vi.waitFor(() => {
      expect(report).toHaveBeenCalledWith("running", "游戏进程已创建，正在等待窗口", 0.9);
    });
    expect(existsSync(join(fixture.sessionDir, "dns-gate"))).toBe(true);

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
    expect(existsSync(join(fixture.sessionDir, "game"))).toBe(false);
  });
});

async function spawned(): Promise<void> {
  await vi.waitFor(() => expect(mocks.spawn).toHaveBeenCalledOnce());
}
