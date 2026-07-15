import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { zstdCompressSync } from "node:zlib";
import { afterEach, expect, test, vi } from "vitest";
import xxhash from "xxhash-wasm";
import { Store } from "../src/core/database";
import { FixtureProvider } from "../src/providers/fixture";
import type { GameAsset, GameBuild } from "../src/providers/provider";
import { GameService } from "../src/services/games";
import { ensureGameConfiguration } from "../src/services/game-config";

const roots: string[] = [];
afterEach(() => { vi.unstubAllGlobals(); for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

test("管理文件拒绝符号链接且不改写目录外目标", () => {
  const root = temp("managed-link-"), game = join(root, "game"), victim = join(root, "victim");
  mkdirSync(game); writeFileSync(victim, "game_version=private\n"); symlinkSync(victim, join(game, "config.ini"));
  expect(() => ensureGameConfiguration(game, "6.6.0")).toThrow("路径包含链接");
  expect(readFileSync(victim, "utf8")).toBe("game_version=private\n");
});

test("健康客户端校验成功而不是空构建失败", async () => {
  const context = serviceContext("6.6.0"), content = "healthy", md5 = hash(content);
  writeFileSync(join(context.game, "YuanShen.exe"), content);
  writeFileSync(join(context.game, "pkg_version"), JSON.stringify({ remoteName: "YuanShen.exe", md5 }));
  writeFileSync(join(context.fixtures, "installed.json"), JSON.stringify({
    version: "6.6.0", assets: [{ name: "YuanShen.exe", size: content.length, md5, chunks: [] }],
  }));
  try { expect((await wait(context.service, await context.service.start("verify", context.game))).status).toBe("completed"); }
  finally { context.store.close(); }
});

test("差分补丁失败后使用完整清单修复并校验未变更文件", async () => {
  const context = serviceContext("6.6.0"), patch = Buffer.from("patch");
  writeFileSync(join(context.game, "YuanShen.exe"), "launcher");
  writeFileSync(join(context.game, "untouched.bin"), "broken!!");
  const repaired = await asset("data.bin", Buffer.from("repaired"), "https://fixture/data");
  const untouched = await asset("untouched.bin", Buffer.from("expected"), "https://fixture/untouched");
  const patchId = `${await xxh(patch)}_patch`;
  const build: Partial<GameBuild> & Pick<GameBuild, "version"> = {
    version: "6.7.0", kind: "version_diff", repair_assets: [repaired, untouched],
    patch_assets: [{ name: "data.bin", size: repaired.size, md5: repaired.md5,
      patch: { id: patchId, file_size: patch.length, start: 0, length: patch.length, original_name: "missing.bin", url: "https://fixture/patch" } }],
  };
  writeFileSync(join(context.fixtures, "build.json"), JSON.stringify(build));
  const payloads = new Map([["https://fixture/patch", patch], ["https://fixture/data", compressed(repaired)], ["https://fixture/untouched", compressed(untouched)]]);
  vi.stubGlobal("fetch", vi.fn(async (url: string) => {
    const value = payloads.get(String(url)); return new Response(value ? new Uint8Array(value) : null);
  }));
  try {
    const job = await wait(context.service, await context.service.start("update", context.game));
    expect({ status: job.status, message: job.message }).toEqual({ status: "completed", message: "正在更新游戏资源" });
    expect(readFileSync(join(context.game, "data.bin"), "utf8")).toBe("repaired");
    expect(readFileSync(join(context.game, "untouched.bin"), "utf8")).toBe("expected");
  } finally { context.store.close(); }
});

function serviceContext(version: string): { root: string; game: string; fixtures: string; store: Store; service: GameService } {
  const root = temp("game-update-"), game = join(root, "game"), fixtures = join(root, "fixtures"), data = join(root, "data");
  mkdirSync(game); mkdirSync(fixtures); writeFileSync(join(game, "config.ini"), `game_version=${version}\n`);
  if (!existsSync(join(fixtures, "build.json"))) writeFileSync(join(fixtures, "build.json"), JSON.stringify({ version }));
  const store = new Store(join(data, "test.db")); return { root, game, fixtures, store, service: new GameService(store, new FixtureProvider(fixtures), data) };
}

async function asset(name: string, content: Buffer, url: string): Promise<GameAsset> {
  const packed = zstdCompressSync(content), chunkName = `${await xxh(packed)}_${name.replaceAll(".", "_")}`;
  return { name, size: content.length, md5: hash(content), chunks: [{ name: chunkName, decompressed_md5: hash(content), offset: 0,
    size: packed.length, decompressed_size: content.length, url }] };
}

function compressed(asset: GameAsset): Buffer { return zstdCompressSync(Buffer.from(asset.name === "data.bin" ? "repaired" : "expected")); }
function hash(value: string | Buffer): string { return createHash("md5").update(value).digest("hex"); }
async function xxh(value: Buffer): Promise<string> { return (await xxhash()).h64Raw(value).toString(16).padStart(16, "0"); }
function temp(prefix: string): string { const value = mkdtempSync(join(tmpdir(), prefix)); roots.push(value); return value; }
async function wait(service: GameService, initial: ReturnType<GameService["get"]>): Promise<ReturnType<GameService["get"]>> {
  let job = initial; for (let i = 0; i < 100 && !["completed", "failed", "cancelled"].includes(job.status); i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 10)); job = service.get(job.id); }
  return job;
}
