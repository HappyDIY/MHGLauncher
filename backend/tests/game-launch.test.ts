import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { prepareDll, type DllIntegrity } from "../src/services/game-launch-files";
import { recoverInterruptedDlls } from "../src/services/game-launch-recovery";
import type { GameLaunchRunner, LaunchReporter, LaunchRunInput } from "../src/services/game-launch-process";
import { GameLaunchService } from "../src/services/game-launches";
import { AppError } from "../src/core/errors";
import { ResourceCoordinator } from "../src/services/resource-coordinator";

const roots: string[] = [];

class FixtureRunner implements GameLaunchRunner {
  constructor(private readonly code = 0) {}
  async run(input: LaunchRunInput, report: LaunchReporter): Promise<number> {
    if (input.networkDebug) {
      writeFileSync(join(input.sessionDir, "dns.log"), "1782140400000\t4321\tgetaddrinfo/A\texample.com\tallowed\t0\t1.2.3.4\n");
    }
    report("starting", "正在创建游戏进程", 0.68);
    report("waiting_window", "正在等待窗口", 0.82);
    report("running", "域名屏蔽已解除", 1);
    return this.code;
  }
}

class BlockingRunner implements GameLaunchRunner {
  async run(input: LaunchRunInput, report: LaunchReporter): Promise<number> {
    report("running", "游戏窗口已显示", 1);
    return await new Promise((resolve) => input.signal.addEventListener("abort", () => resolve(0), { once: true }));
  }
}

class FailingRunner implements GameLaunchRunner {
  async run(): Promise<number> { throw new Error("spawn ENOENT: /private/runtime/wine64"); }
}

class StopFailingRunner implements GameLaunchRunner {
  async run(): Promise<number> { throw new AppError("wine_server_stop_failed", "Wine 服务未确认退出", 500); }
}

describe("游戏启动会话", () => {
  afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

  test("启动期间替换 DLL 并在退出后恢复", async () => {
    const fixture = makeFixture();
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: true, network_debug: true, wine_log: false, frame_pacing: 60 });
    await waitFor(() => service.get(launch.id).status === "exited");
    expect(readFileSync(join(fixture.game, "mhypbase.dll"), "utf8")).toBe("original-dll");
    expect(service.get(launch.id)).toMatchObject({ status: "exited", metal_hud: true, progress: 1 });
    expect(service.get(launch.id).logs.map((entry) => entry.message)).toContain("域名屏蔽已解除");
    expect(service.get(launch.id).logs.map((entry) => entry.message)).toContain(
      "DNS · PID 4321 · getaddrinfo/A · example.com · 成功 → 1.2.3.4",
    );
  });

  test("没有原 DLL 时退出后删除注入副本", async () => {
    const fixture = makeFixture(false);
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "compatibility", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 });
    await waitFor(() => service.get(launch.id).status === "exited");
    expect(existsSync(join(fixture.game, "mhypbase.dll"))).toBe(false);
  });

  test("停止游戏后终止会话并恢复 DLL", async () => {
    const fixture = makeFixture();
    const service = new GameLaunchService(fixture.data, fixture.runtime, new BlockingRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 });
    await waitFor(() => service.get(launch.id).status === "running");
    expect(service.stop(launch.id).status).toBe("stopping");
    await waitFor(() => service.get(launch.id).status === "stopped");
    expect(readFileSync(join(fixture.game, "mhypbase.dll"), "utf8")).toBe("original-dll");
  });

  test("启动会话长轮询会在状态更新后返回", async () => {
    const fixture = makeFixture();
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 });
    const revision = launch.revision ?? 0;
    const updated = await service.wait(launch.id, revision, 1_000);
    expect(updated.revision).toBeGreaterThan(revision);
  });

  test("启动器异常不会写入面向用户的会话消息", async () => {
    const fixture = makeFixture();
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FailingRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 });
    await waitFor(() => service.get(launch.id).status === "failed");
    expect(service.get(launch.id).message).toBe("游戏启动失败，请稍后重试");
  });

  test("下次服务启动恢复中断的 DLL 事务", () => {
    const fixture = makeFixture();
    const session = join(fixture.data, "launches", "interrupted");
    prepareDll(fixture.game, join(fixture.runtime, "assets", "mhypbase.dll"), session, fixture.integrity);
    expect(readFileSync(join(fixture.game, "mhypbase.dll"), "utf8")).toBe("verified-fixture-dll");
    expect(recoverInterruptedDlls(fixture.data)).toEqual({ warnings: [], pending: false });
    expect(readFileSync(join(fixture.game, "mhypbase.dll"), "utf8")).toBe("original-dll");
    expect(existsSync(join(session, "dll-journal.json"))).toBe(false);
  });

  test("恢复保留原 DLL 权限并消费成功 journal", async () => {
    const fixture = makeFixture(), target = join(fixture.game, "mhypbase.dll"); chmodSync(target, 0o755);
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 });
    await waitFor(() => service.get(launch.id).status === "exited");
    expect(statSync(target).mode & 0o777).toBe(0o755);
    expect(existsSync(join(fixture.data, "launches", launch.id, "dll-journal.json"))).toBe(false);
  });

  test("外部修改时保留恢复记录供后续重试", () => {
    const fixture = makeFixture(), session = join(fixture.data, "launches", "interrupted");
    prepareDll(fixture.game, join(fixture.runtime, "assets", "mhypbase.dll"), session, fixture.integrity);
    writeFileSync(join(fixture.game, "mhypbase.dll"), "external");
    const result = recoverInterruptedDlls(fixture.data);
    expect(result.pending).toBe(true); expect(result.warnings[0]).toContain("恢复记录已保留");
    expect(existsSync(join(session, "dll-journal.json"))).toBe(true);
  });

  test("伪造的 DLL 恢复目标不会删除游戏目录外文件", () => {
    const fixture = makeFixture(), session = join(fixture.data, "launches", "forged");
    const outside = join(fixture.data, "outside"), target = join(outside, "mhypbase.dll"), journal = join(session, "dll-journal.json");
    mkdirSync(session, { recursive: true }); mkdirSync(outside); writeFileSync(target, "keep");
    writeFileSync(journal, JSON.stringify({
      schema: 2, generation: "forged", phase: "installed", journal_path: journal,
      target, backup: join(session, "mhypbase.original.dll"), original_exists: false,
      original_sha256: "", original_mode: 0o644, original_dev: "", original_ino: "",
      replacement_md5: createHash("md5").update("keep").digest("hex"),
    }));
    const result = recoverInterruptedDlls(fixture.data);
    expect(result).toMatchObject({ pending: true });
    expect(readFileSync(target, "utf8")).toBe("keep"); expect(existsSync(journal)).toBe(true);
  });

  test("重启后重新加载持久会话并完成 DLL 恢复", async () => {
    const fixture = makeFixture(), first = new GameLaunchService(fixture.data, fixture.runtime, new BlockingRunner(), fixture.integrity);
    const launch = first.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 });
    await waitFor(() => first.get(launch.id).status === "running");
    const restarted = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity);
    expect(restarted.get(launch.id).status).toBe("exited");
    first.stop(launch.id); await waitFor(() => first.get(launch.id).status === "stopped"); restarted.close();
  });

  test("初始状态持久化失败不会发布幽灵会话", () => {
    const fixture = makeFixture(), service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity);
    mkdirSync(fixture.data, { recursive: true });
    writeFileSync(join(fixture.data, "launches"), "blocked");
    expect(() => service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 })).toThrow();
    expect(service.active()).toBe(false);
  });

  test("资源任务占用同一安装目录时拒绝启动", () => {
    const fixture = makeFixture(), coordinator = new ResourceCoordinator(), lease = coordinator.claim(fixture.game, "resource-job");
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity, coordinator);
    expect(() => service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 })).toThrow("正在被其他任务使用");
    coordinator.release(lease); expect(service.active()).toBe(false);
  });

  test("停止确认失败发布终态并交由恢复守护任务", async () => {
    const fixture = makeFixture(), service = new GameLaunchService(fixture.data, fixture.runtime, new StopFailingRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 });
    await waitFor(() => service.get(launch.id).status === "failed");
    expect(service.get(launch.id).message).toContain("Wine 服务未确认退出"); expect(service.active()).toBe(false);
  });
});

function makeFixture(original = true): { data: string; runtime: string; game: string; integrity: DllIntegrity } {
  const root = mkdtempSync(join(tmpdir(), "mhg-launch-")); roots.push(root);
  const data = join(root, "data"), runtime = join(root, "runtime"), game = join(root, "game");
  mkdirSync(join(runtime, "assets"), { recursive: true }); mkdirSync(game, { recursive: true });
  writeFileSync(join(game, "YuanShen.exe"), "fixture"); writeFileSync(join(game, "config.ini"), "game_version=5.0.0\n");
  if (original) writeFileSync(join(game, "mhypbase.dll"), "original-dll");
  const replacement = Buffer.from("verified-fixture-dll"); writeFileSync(join(runtime, "assets", "mhypbase.dll"), replacement);
  return { data, runtime, game, integrity: {
    size: replacement.length, md5: createHash("md5").update(replacement).digest("hex"),
    sha256: createHash("sha256").update(replacement).digest("hex"),
  } };
}

async function waitFor(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  throw new Error("等待启动状态超时");
}
