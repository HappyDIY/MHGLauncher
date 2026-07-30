import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { commitDll, prepareDll, restoreDll, type DllIntegrity } from "../src/services/game-launch-files";
import { recoverInterruptedDlls } from "../src/services/game-launch-recovery";
import type { GameLaunchRunner, LaunchReporter, LaunchRunInput } from "../src/services/game-launch-process";
import { GameLaunchService } from "../src/services/game-launches";
import { AppError } from "../src/core/errors";
import { ResourceCoordinator } from "../src/services/resource-coordinator";

const roots: string[] = [];
const base = { performance_profile: "optimized" as const, metal_hud: false, network_debug: false, wine_log: false, frame_pacing: 0 };
const dll = (game: string) => join(game, "mhypbase.dll");
const svc = (f: ReturnType<typeof makeFixture>, r: GameLaunchRunner = new FixtureRunner()) => new GameLaunchService(f.data, f.runtime, r, f.integrity);

class FixtureRunner implements GameLaunchRunner {
  lastInput?: LaunchRunInput;
  constructor(private readonly code = 0) {}
  async run(input: LaunchRunInput, report: LaunchReporter): Promise<number> {
    this.lastInput = input;
    if (input.networkDebug) {
      writeFileSync(join(input.sessionDir, "dns.log"), "1782140400000\t4321\tgetaddrinfo/A\texample.com\tallowed\t0\t1.2.3.4\n");
    }
    report("starting", "正在创建游戏进程", 0.68); report("waiting_window", "正在等待窗口", 0.82);
    report("running", "域名屏蔽已解除", 1); return this.code;
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
function markPlanned(session: string): string {
  const path = join(session, "dll-journal.json");
  const journal = JSON.parse(readFileSync(path, "utf8")) as { phase: string };
  journal.phase = "planned"; writeFileSync(path, JSON.stringify(journal)); return path;
}

describe("游戏启动会话", () => {
  afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

  test("启动期间替换 DLL 并在退出后保留", async () => {
    const fixture = makeFixture(), runner = new FixtureRunner(), service = svc(fixture, runner);
    const launch = service.start({
      install_path: fixture.game, performance_profile: "optimized", metal_hud: true, network_debug: true,
      wine_log: false, frame_pacing: 60, launch_arguments: "-popupwindow",
    });
    await waitFor(() => service.get(launch.id).status === "exited");
    expect(readFileSync(dll(fixture.game), "utf8")).toBe("verified-fixture-dll");
    expect(existsSync(join(fixture.data, "launches", launch.id, "dll-journal.json"))).toBe(false);
    expect(service.get(launch.id)).toMatchObject({ status: "exited", metal_hud: true, progress: 1 });
    expect(service.get(launch.id).logs.map((e) => e.message)).toContain("域名屏蔽已解除");
    expect(runner.lastInput?.launchArguments).toBe("-popupwindow");
    expect(service.get(launch.id).logs.map((e) => e.message)).toContain(
      "DNS · PID 4321 · getaddrinfo/A · example.com · 成功 → 1.2.3.4",
    );
  });

  test("没有原 DLL 时退出后保留注入副本", async () => {
    const fixture = makeFixture(false), service = svc(fixture);
    const launch = service.start({ install_path: fixture.game, ...base, performance_profile: "compatibility" });
    await waitFor(() => service.get(launch.id).status === "exited");
    expect(readFileSync(dll(fixture.game), "utf8")).toBe("verified-fixture-dll");
  });

  test("停止游戏后终止会话并保留 DLL", async () => {
    const fixture = makeFixture(), service = svc(fixture, new BlockingRunner());
    const launch = service.start({ install_path: fixture.game, ...base });
    await waitFor(() => service.get(launch.id).status === "running");
    expect(service.stop(launch.id).status).toBe("stopping");
    await waitFor(() => service.get(launch.id).status === "stopped");
    expect(readFileSync(dll(fixture.game), "utf8")).toBe("verified-fixture-dll");
  });

  test("启动会话长轮询会在状态更新后返回", async () => {
    const fixture = makeFixture(), service = svc(fixture);
    const launch = service.start({ install_path: fixture.game, ...base }), revision = launch.revision ?? 0;
    expect((await service.wait(launch.id, revision, 1_000)).revision).toBeGreaterThan(revision);
  });

  test("启动器异常不会写入面向用户的会话消息", async () => {
    const fixture = makeFixture(), service = svc(fixture, new FailingRunner());
    const launch = service.start({ install_path: fixture.game, ...base });
    await waitFor(() => service.get(launch.id).status === "failed");
    expect(service.get(launch.id).message).toBe("游戏启动失败，请稍后重试");
  });

  test("installed 会话清理保留 DLL，planned 中断回滚", () => {
    const fixture = makeFixture(), session = join(fixture.data, "launches", "interrupted");
    const source = join(fixture.runtime, "assets", "mhypbase.dll"), target = dll(fixture.game);
    prepareDll(fixture.game, source, session, fixture.integrity);
    expect(readFileSync(target, "utf8")).toBe("verified-fixture-dll");
    expect(recoverInterruptedDlls(fixture.data)).toEqual({ warnings: [], pending: false });
    expect(readFileSync(target, "utf8")).toBe("verified-fixture-dll");
    expect(existsSync(join(session, "dll-journal.json"))).toBe(false);
    writeFileSync(target, "original-dll"); prepareDll(fixture.game, source, session, fixture.integrity);
    const journalPath = markPlanned(session);
    expect(recoverInterruptedDlls(fixture.data)).toEqual({ warnings: [], pending: false });
    expect(readFileSync(target, "utf8")).toBe("original-dll"); expect(existsSync(journalPath)).toBe(false);
  });

  test("替换保留原 DLL 权限并消费成功 journal", async () => {
    const fixture = makeFixture(), target = dll(fixture.game); chmodSync(target, 0o755);
    const service = svc(fixture), launch = service.start({ install_path: fixture.game, ...base });
    await waitFor(() => service.get(launch.id).status === "exited");
    expect(statSync(target).mode & 0o777).toBe(0o755);
    expect(readFileSync(target, "utf8")).toBe("verified-fixture-dll");
    expect(existsSync(join(fixture.data, "launches", launch.id, "dll-journal.json"))).toBe(false);
  });

  test("planned 外部修改保留记录，restore/commit 边界分支", () => {
    const fixture = makeFixture(), session = join(fixture.data, "launches", "interrupted");
    const source = join(fixture.runtime, "assets", "mhypbase.dll"), target = dll(fixture.game);
    const journal = prepareDll(fixture.game, source, session, fixture.integrity)!;
    markPlanned(session); writeFileSync(target, "external");
    expect(recoverInterruptedDlls(fixture.data).pending).toBe(true);
    expect(restoreDll(null).pending).toBe(false); expect(commitDll(null).pending).toBe(false);
    expect(restoreDll({ ...journal, schema: 1 as 2 }).pending).toBe(true);
    writeFileSync(target, "original-dll"); expect(restoreDll(journal)).toEqual({ warning: "", pending: false });
    prepareDll(fixture.game, source, session, fixture.integrity);
    expect(prepareDll(fixture.game, source, session, fixture.integrity)).toBeNull();
    rmSync(target, { force: true });
    expect(restoreDll({ ...journal, original_exists: false, original_sha256: "" })).toEqual({ warning: "", pending: false });
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
    expect(recoverInterruptedDlls(fixture.data)).toMatchObject({ pending: true });
    expect(readFileSync(target, "utf8")).toBe("keep"); expect(existsSync(journal)).toBe(true);
  });

  test("重启后重新加载持久会话并完成 DLL 会话清理", async () => {
    const fixture = makeFixture(), first = svc(fixture, new BlockingRunner());
    const launch = first.start({ install_path: fixture.game, ...base });
    await waitFor(() => first.get(launch.id).status === "running");
    const restarted = svc(fixture); expect(restarted.get(launch.id).status).toBe("exited");
    first.stop(launch.id); await waitFor(() => first.get(launch.id).status === "stopped"); restarted.close();
  });

  test("初始状态持久化失败不会发布幽灵会话", () => {
    const fixture = makeFixture(), service = svc(fixture);
    mkdirSync(fixture.data, { recursive: true }); writeFileSync(join(fixture.data, "launches"), "blocked");
    expect(() => service.start({ install_path: fixture.game, ...base })).toThrow();
    expect(service.active()).toBe(false);
  });

  test("资源任务占用同一安装目录时拒绝启动", () => {
    const fixture = makeFixture(), coordinator = new ResourceCoordinator(), lease = coordinator.claim(fixture.game, "resource-job");
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity, coordinator);
    expect(() => service.start({ install_path: fixture.game, ...base })).toThrow("正在被其他任务使用");
    coordinator.release(lease); expect(service.active()).toBe(false);
  });

  test("停止确认失败发布终态并交由恢复守护任务", async () => {
    const fixture = makeFixture(), service = svc(fixture, new StopFailingRunner());
    const launch = service.start({ install_path: fixture.game, ...base });
    await waitFor(() => service.get(launch.id).status === "failed");
    expect(service.get(launch.id).message).toContain("Wine 服务未确认退出"); expect(service.active()).toBe(false);
  });
});

function makeFixture(original = true): { data: string; runtime: string; game: string; integrity: DllIntegrity } {
  const root = mkdtempSync(join(tmpdir(), "mhg-launch-")); roots.push(root);
  const data = join(root, "data"), runtime = join(root, "runtime"), game = join(root, "game");
  mkdirSync(join(runtime, "assets"), { recursive: true }); mkdirSync(game, { recursive: true });
  writeFileSync(join(game, "YuanShen.exe"), "fixture"); writeFileSync(join(game, "config.ini"), "game_version=5.0.0\n");
  if (original) writeFileSync(dll(game), "original-dll");
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
