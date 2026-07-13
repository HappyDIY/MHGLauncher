import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { beforeEach, expect, test, vi } from "vitest";
import { fixture, request } from "./helpers";
import { prepareBuild } from "../src/services/game-build";
import { normalizeBuild } from "../src/providers/provider";
import { Store } from "../src/core/database";
import { GameService } from "../src/services/games";
import { FixtureProvider } from "../src/providers/fixture";
import { ResourceCoordinator } from "../src/services/resource-coordinator";

beforeEach(() => fixture());
test("检测官方游戏目录版本", async () => {
  const root = mkdtempSync(join(tmpdir(), "game-")), game = join(root, "Genshin Impact Game"); mkdirSync(game);
  writeFileSync(join(game, "YuanShen.exe"), ""); writeFileSync(join(game, "config.ini"), "[General]\ngame_version=5.7.0\n");
  const response = await request("GET", `/v1/game/status/path?install_path=${encodeURIComponent(game)}`), value = await response.json();
  expect(value.installed_version).toBe("5.7.0"); expect(value.status).toBe("update_available");
});
test("官方版本覆盖旧启动器版本标记", async () => {
  const game = mkdtempSync(join(tmpdir(), "game-"));
  writeFileSync(join(game, "YuanShen.exe"), ""); writeFileSync(join(game, "config.ini"), "game_version=5.8.0\n"); writeFileSync(join(game, ".mhg-version"), "5.7.0");
  const value = await (await request("GET", `/v1/game/status/path?install_path=${encodeURIComponent(game)}`)).json();
  expect(value.installed_version).toBe("5.8.0"); expect(value.status).toBe("ready");
});
test("仅有版本标记不视为已安装", async () => {
  const game = mkdtempSync(join(tmpdir(), "empty-game-"));
  writeFileSync(join(game, ".mhg-version"), "6.6.0");
  const response = await request("GET", `/v1/game/status/path?install_path=${encodeURIComponent(game)}`);
  expect((await response.json()).status).toBe("not_installed");
});
test("未安装时禁止更新", async () => expect((await request("POST", "/v1/game/jobs", { kind: "update", install_path: "/tmp/missing" })).status).toBe(400));
test("预下载空间检查使用预下载构建", async () => {
  const game = mkdtempSync(join(tmpdir(), "game-"));
  writeFileSync(join(game, "YuanShen.exe"), ""); writeFileSync(join(game, ".mhg-version"), "5.8.0");
  const info = await (await request("GET", `/v1/game/space-check?kind=predownload&install_path=${encodeURIComponent(game)}`)).json();
  expect(info.required).toBe(1073741825);
});
test("预下载前要求常规通道与本机版本一致", async () => {
  const game = mkdtempSync(join(tmpdir(), "game-"));
  writeFileSync(join(game, "YuanShen.exe"), ""); writeFileSync(join(game, ".mhg-version"), "5.7.0");
  const response = await request("GET", `/v1/game/space-check?kind=predownload&install_path=${encodeURIComponent(game)}`);
  expect(response.status).toBe(409);
  expect((await response.json()).code).toBe("predownload_base_mismatch");
});
test("常驻资源目录清单不视为待下载内容", () => {
  const root = mkdtempSync(join(tmpdir(), "hotfix-")), persistent = join(root, "YuanShen_Data/Persistent"); mkdirSync(persistent, { recursive: true });
  writeFileSync(join(persistent, "data_versions_remote"), JSON.stringify({ fileSize: 12 }));
  expect(prepareBuild(normalizeBuild({ version: "1" }), root, "1")).toMatchObject({ kind: "full", pending_bytes: 0 });
});
test("无热更新保持构建", () => expect(prepareBuild(normalizeBuild({ version: "1" }), "/tmp/missing", "1").kind).toBe("full"));
test("忽略启动器托管的反作弊 DLL", () => {
  const build = prepareBuild(normalizeBuild({
    version: "2",
    assets: [
      { name: "mhypbase.dll", size: 1, md5: "a", chunks: [] },
      { name: "YuanShen.exe", size: 2, md5: "b", chunks: [] },
    ],
    patch_assets: [
      { name: "mhypbase.dll", size: 1, md5: "a", patch: { id: "p1", file_size: 1, start: 0, length: 1, original_name: "mhypbase.dll", url: "" } },
      { name: "config.ini", size: 2, md5: "b", patch: { id: "p2", file_size: 2, start: 0, length: 2, original_name: "config.ini", url: "" } },
    ],
    deprecated_files: ["mhypbase.dll", "old.dat"],
  }), "/tmp/missing", "1");
  expect(build.assets.map((asset) => asset.name)).toEqual(["YuanShen.exe"]);
  expect(build.patch_assets.map((asset) => asset.name)).toEqual(["config.ini"]);
  expect(build.deprecated_files).toEqual(["old.dat"]);
});

test("Sophon 更新通过暂存目录原子提交且取消终态任务幂等", async () => {
  const root = mkdtempSync(join(tmpdir(), "in-place-update-")), data = join(root, "data"), fixtures = join(root, "fixtures"), game = join(root, "Genshin Impact Game");
  mkdirSync(fixtures, { recursive: true }); mkdirSync(game);
  const exe = "same-binary", md5 = createHash("md5").update(exe).digest("hex");
  writeFileSync(join(game, "YuanShen.exe"), exe); writeFileSync(join(game, "config.ini"), "game_version=5.7.0\n");
  writeFileSync(join(fixtures, "build.json"), JSON.stringify({ version: "5.8.0", assets: [{ name: "YuanShen.exe", size: exe.length, md5, chunks: [] }] }));
  const store = new Store(join(data, "test.db")), service = new GameService(store, new FixtureProvider(fixtures), data);
  try {
    let job = await service.start("update", game);
    for (let i = 0; i < 20 && !["completed", "failed", "cancelled"].includes(job.status); i += 1) {
      await new Promise((resolve) => setTimeout(resolve, 10)); job = service.get(job.id);
    }
    expect(job.status).toBe("completed"); expect(readdirSync(root).some((name) => name.includes("mhg-staging"))).toBe(false);
    expect(service.control(job.id, "cancel").status).toBe("completed");
  } finally { store.close(); rmSync(root, { recursive: true, force: true }); }
});

test("仅含删除项的差分完成删除后才更新版本", async () => {
  const { root, game, service, store } = serviceFor({ version: "5.8.0", kind: "version_diff", deprecated_files: ["old.dat"] });
  writeFileSync(join(game, "old.dat"), "old");
  try {
    const job = await waitJob(service, await service.start("update", game));
    expect(job.status).toBe("completed"); expect(existsSync(join(game, "old.dat"))).toBe(false);
  } finally { store.close(); rmSync(root, { recursive: true, force: true }); }
});

test("不同版本的空构建被拒绝且保留原目录", async () => {
  const { root, game, service, store } = serviceFor({ version: "5.8.0" });
  try {
    await expect(service.start("update", game)).rejects.toMatchObject({ code: "game_build_empty" });
    expect(existsSync(join(game, "YuanShen.exe"))).toBe(true);
  } finally { store.close(); rmSync(root, { recursive: true, force: true }); }
});

test("资源任务在首个 await 前占用安装目录", async () => {
  const root = mkdtempSync(join(tmpdir(), "game-reservation-")), data = join(root, "data"), fixtures = join(root, "fixtures"), game = join(root, "game");
  mkdirSync(fixtures); mkdirSync(game); writeFileSync(join(game, "YuanShen.exe"), "game"); writeFileSync(join(game, "config.ini"), "game_version=5.7.0\n");
  const provider = new FixtureProvider(fixtures), gate = Promise.withResolvers<Awaited<ReturnType<FixtureProvider["getBuild"]>>>();
  vi.spyOn(provider, "getBuild").mockReturnValue(gate.promise);
  const store = new Store(join(data, "test.db")), service = new GameService(store, provider, data, 4, 0, new ResourceCoordinator());
  try {
    const first = service.start("update", game); await Promise.resolve();
    await expect(service.start("update", game)).rejects.toMatchObject({ code: "game_resource_busy" });
    gate.resolve(normalizeBuild({ version: "5.8.0", kind: "version_diff", deprecated_files: ["old.dat"] }));
    expect((await waitJob(service, await first)).status).toBe("completed");
  } finally { store.close(); rmSync(root, { recursive: true, force: true }); }
});

function serviceFor(build: Record<string, unknown>): { root: string; game: string; service: GameService; store: Store } {
  const root = mkdtempSync(join(tmpdir(), "game-transaction-")), data = join(root, "data"), fixtures = join(root, "fixtures"), game = join(root, "game");
  mkdirSync(fixtures); mkdirSync(game); writeFileSync(join(game, "YuanShen.exe"), "game"); writeFileSync(join(game, "config.ini"), "game_version=5.7.0\n");
  writeFileSync(join(fixtures, "build.json"), JSON.stringify(build));
  const store = new Store(join(data, "test.db"));
  return { root, game, store, service: new GameService(store, new FixtureProvider(fixtures), data) };
}

async function waitJob(service: GameService, initial: Awaited<ReturnType<GameService["start"]>>): Promise<ReturnType<GameService["get"]>> {
  let job = initial;
  for (let index = 0; index < 30 && !["completed", "failed", "cancelled"].includes(job.status); index += 1) {
    await new Promise((resolve) => setTimeout(resolve, 10)); job = service.get(job.id);
  }
  return job;
}
