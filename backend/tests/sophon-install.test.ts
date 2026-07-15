import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { zstdCompressSync } from "node:zlib";
import { expect, test, vi } from "vitest";
import xxhash from "xxhash-wasm";
import type { GameAsset } from "../src/providers/provider";
import { DownloadControl } from "../src/services/download";
import { installSophon } from "../src/services/sophon-install";

test("安装成功后释放分块缓存", async () => {
  const root = mkdtempSync(join(tmpdir(), "sophon-install-")), staging = join(root, "staging"), cache = join(root, "cache");
  const content = Buffer.from("分块内容"), compressed = zstdCompressSync(content);
  const prefix = (await xxhash()).h64Raw(compressed).toString(16).padStart(16, "0"), name = `${prefix}_fixture`;
  const chunk = { name, decompressed_md5: md5(content), offset: 0, size: compressed.length, decompressed_size: content.length, url: "https://fixture/chunk" };
  const assets: GameAsset[] = ["first.bin", "second.bin"].map((assetName) => ({ name: assetName, size: content.length, md5: md5(content), chunks: [chunk] }));
  vi.stubGlobal("fetch", vi.fn(async () => new Response(compressed)));

  await installSophon(assets, staging, cache, new DownloadControl(), () => undefined, () => undefined);

  expect(readFileSync(join(staging, "first.bin"))).toEqual(content);
  expect(readFileSync(join(staging, "second.bin"))).toEqual(content);
  expect(existsSync(join(cache, name))).toBe(false);
  expect(fetch).toHaveBeenCalledTimes(1);
  vi.unstubAllGlobals();
});

test("修复失败时保留原文件", async () => {
  const root = mkdtempSync(join(tmpdir(), "sophon-atomic-")), cache = join(root, "cache"), target = join(root, "game.bin");
  const content = Buffer.from("新内容"), compressed = zstdCompressSync(content);
  const prefix = (await xxhash()).h64Raw(compressed).toString(16).padStart(16, "0"), name = `${prefix}_atomic`;
  const chunk = { name, decompressed_md5: md5(content), offset: 0, size: compressed.length, decompressed_size: content.length, url: "https://fixture/chunk" };
  const asset: GameAsset = { name: "game.bin", size: content.length, md5: "0".repeat(32), chunks: [chunk] };
  writeFileSync(target, "原文件");
  vi.stubGlobal("fetch", vi.fn(async () => new Response(compressed)));

  await expect(installSophon([asset], root, cache, new DownloadControl(), () => undefined, () => undefined)).rejects.toThrow("文件校验失败");

  expect(readFileSync(target, "utf8")).toBe("原文件");
  expect(existsSync(`${target}.${process.pid}.mhg-installing`)).toBe(false);
  vi.unstubAllGlobals();
});

test("同一资源内的重复分块只下载一次", async () => {
  const root = mkdtempSync(join(tmpdir(), "sophon-duplicate-")), cache = join(root, "cache");
  const content = Buffer.from("same"), packed = zstdCompressSync(content), name = `${await hash64(packed)}_duplicate`;
  const chunks = [0, content.length].map((offset) => ({ name, decompressed_md5: md5(content), offset,
    size: packed.length, decompressed_size: content.length, url: "https://fixture/duplicate" }));
  const full = Buffer.concat([content, content]);
  vi.stubGlobal("fetch", vi.fn(async () => new Response(packed)));
  await installSophon([{ name: "duplicate.bin", size: full.length, md5: md5(full), chunks }], root, cache,
    new DownloadControl(), () => undefined, () => undefined, 2);
  expect(readFileSync(join(root, "duplicate.bin"))).toEqual(full);
  expect(fetch).toHaveBeenCalledTimes(1);
  vi.unstubAllGlobals();
});

test("正式更新复用本地分块和预下载缓存", async () => {
  const root = mkdtempSync(join(tmpdir(), "sophon-diff-")), cache = join(root, "cache"); mkdirSync(cache);
  const shared = Buffer.from("shared"), old = Buffer.from("old"), next = Buffer.from("next");
  const sharedChunk = await chunk(shared, 0, "shared"), oldChunk = await chunk(old, shared.length, "old");
  const nextChunk = await chunk(next, shared.length, "next");
  const localContent = Buffer.concat([shared, old]), remoteContent = Buffer.concat([shared, next]);
  const base: GameAsset = { name: "game.bin", size: localContent.length, md5: md5(localContent), chunks: [sharedChunk, oldChunk] };
  const remote: GameAsset = { name: "game.bin", size: remoteContent.length, md5: md5(remoteContent),
    chunks: [sharedChunk, nextChunk], required_chunks: [nextChunk] };
  writeFileSync(join(root, "game.bin"), localContent); writeFileSync(join(cache, nextChunk.name), zstdCompressSync(next));
  vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("不应重新下载"); }));
  await installSophon([remote], root, cache, new DownloadControl(), () => undefined, () => undefined, 2, undefined, [base]);
  expect(readFileSync(join(root, "game.bin"))).toEqual(remoteContent);
  expect(fetch).not.toHaveBeenCalled();
  vi.unstubAllGlobals();
});

function md5(value: Buffer): string { return createHash("md5").update(value).digest("hex"); }
async function hash64(value: Buffer): Promise<string> { return (await xxhash()).h64Raw(value).toString(16).padStart(16, "0"); }
async function chunk(value: Buffer, offset: number, suffix: string) {
  const packed = zstdCompressSync(value); return { name: `${await hash64(packed)}_${suffix}`,
    decompressed_md5: md5(value), offset, size: packed.length, decompressed_size: value.length, url: `https://fixture/${suffix}` };
}
