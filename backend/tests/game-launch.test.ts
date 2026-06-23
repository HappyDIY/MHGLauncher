import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { prepareDll, type DllIntegrity } from "../src/services/game-launch-files";
import { recoverInterruptedDlls } from "../src/services/game-launch-recovery";
import type { GameLaunchRunner, LaunchReporter, LaunchRunInput } from "../src/services/game-launch-process";
import { GameLaunchService } from "../src/services/game-launches";

const roots: string[] = [];

class FixtureRunner implements GameLaunchRunner {
  constructor(private readonly code = 0) {}
  async run(input: LaunchRunInput, report: LaunchReporter): Promise<number> {
    if (input.networkDebug) {
      writeFileSync(join(input.sessionDir, "dns.log"), "1782140400000\t4321\tgetaddrinfo\texample.com\tallowed\t0\n");
    }
    report("starting", "正在创建游戏进程", 0.68);
    report("waiting_window", "正在等待窗口", 0.82);
    report("running", "域名屏蔽已解除", 1);
    return this.code;
  }
}

describe("游戏启动会话", () => {
  afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

  test("启动期间替换 DLL 并在退出后恢复", async () => {
    const fixture = makeFixture();
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "optimized", metal_hud: true, network_debug: true, frame_pacing: 60 });
    await waitFor(() => service.get(launch.id).status === "exited");
    expect(readFileSync(join(fixture.game, "mhypbase.dll"), "utf8")).toBe("original-dll");
    expect(service.get(launch.id)).toMatchObject({ status: "exited", metal_hud: true, progress: 1 });
    expect(service.get(launch.id).logs.map((entry) => entry.message)).toContain("域名屏蔽已解除");
    expect(service.get(launch.id).logs.map((entry) => entry.message)).toContain(
      "DNS · PID 4321 · getaddrinfo · example.com · 成功",
    );
  });

  test("没有原 DLL 时退出后删除注入副本", async () => {
    const fixture = makeFixture(false);
    const service = new GameLaunchService(fixture.data, fixture.runtime, new FixtureRunner(), fixture.integrity);
    const launch = service.start({ install_path: fixture.game, performance_profile: "compatibility", metal_hud: false, network_debug: false, frame_pacing: 0 });
    await waitFor(() => service.get(launch.id).status === "exited");
    expect(existsSync(join(fixture.game, "mhypbase.dll"))).toBe(false);
  });

  test("下次服务启动恢复中断的 DLL 事务", () => {
    const fixture = makeFixture();
    const session = join(fixture.data, "launches", "interrupted");
    prepareDll(fixture.game, join(fixture.runtime, "assets", "mhypbase.dll"), session, fixture.integrity);
    expect(readFileSync(join(fixture.game, "mhypbase.dll"), "utf8")).toBe("verified-fixture-dll");
    expect(recoverInterruptedDlls(fixture.data)).toEqual([]);
    expect(readFileSync(join(fixture.game, "mhypbase.dll"), "utf8")).toBe("original-dll");
    expect(existsSync(join(session, "dll-journal.json.restored"))).toBe(true);
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
