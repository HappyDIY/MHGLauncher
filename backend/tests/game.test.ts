import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { beforeEach, expect, test } from "vitest";
import { fixture, request } from "./helpers";
import { prepareBuild } from "../src/services/game-build";
import { normalizeBuild } from "../src/providers/provider";

beforeEach(() => fixture());
test("检测官方游戏目录版本", async () => {
  const root = mkdtempSync(join(tmpdir(), "game-")), game = join(root, "Genshin Impact Game"); mkdirSync(game);
  writeFileSync(join(game, "YuanShen.exe"), ""); writeFileSync(join(game, "config.ini"), "[General]\ngame_version=5.7.0\n");
  const response = await request("GET", `/v1/game/status/path?install_path=${encodeURIComponent(game)}`), value = await response.json();
  expect(value.installed_version).toBe("5.7.0"); expect(value.status).toBe("update_available");
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
