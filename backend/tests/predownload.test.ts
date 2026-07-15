import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { zstdCompressSync } from "node:zlib";
import { expect, test, vi } from "vitest";
import xxhash from "xxhash-wasm";
import type { GameAsset, SophonChunk } from "../src/providers/provider";
import { normalizeBuild } from "../src/providers/provider";
import { checkedPredownloadBuild, compareGameVersions, diffPredownloadBuild } from "../src/services/predownload-build";
import { downloadChunksOnly } from "../src/services/predownload";
import { DownloadControl } from "../src/services/download";
import { predownloadCachedBytes, predownloadDigest, readPredownloadStatus, writePredownloadStatus } from "../src/services/predownload-status";

test("预下载只计算本地缺失的差异分块", () => {
  const shared = chunk("shared", "same"), old = chunk("old", "old"), next = chunk("next", "next");
  const local = normalizeBuild({ version: "6.6.0", assets: [
    asset("data.bin", "old-md5", [shared, old]), asset("retired.bin", "retired", [old]),
  ] });
  const remote = normalizeBuild({ version: "6.7.0", assets: [
    asset("data.bin", "new-md5", [shared, next]), asset("new.bin", "new-file", [chunk("added", "added")]),
  ], is_predownload: true });

  const diff = diffPredownloadBuild(local, remote);

  expect(diff.assets.map((value) => value.name)).toEqual(["data.bin", "new.bin"]);
  expect(diff.assets[0]?.required_chunks?.map((value) => value.name)).toEqual(["next"]);
  expect(diff.assets[1]?.required_chunks).toBeUndefined();
  expect(diff.deprecated_files).toEqual(["retired.bin"]);
});

test("预下载要求本地完整清单与本机版本一致", () => {
  const local = normalizeBuild({ version: "6.7.0" });
  const remote = normalizeBuild({ version: "6.8.0", is_predownload: true });
  expect(() => checkedPredownloadBuild("6.6.0", local, remote)).toThrow("无法计算预下载差分");
});

test("版本比较按数值分段且拒绝相同或更旧的预下载", () => {
  expect(compareGameVersions("6.10.0", "6.9.9")).toBeGreaterThan(0);
  expect(compareGameVersions("6.8", "6.8.0")).toBe(0);
  const local = normalizeBuild({ version: "6.8.0" });
  expect(() => checkedPredownloadBuild("6.8.0", local, normalizeBuild({ version: "6.8.0" }))).toThrow("不高于当前游戏版本");
});

test("预下载完成后保留分块缓存", async () => {
  const root = mkdtempSync(join(tmpdir(), "predownload-")), cache = join(root, "cache");
  const content = Buffer.from("预下载分块"), compressed = zstdCompressSync(content);
  const prefix = (await xxhash()).h64Raw(compressed).toString(16).padStart(16, "0");
  const name = `${prefix}_predownload`, entry = chunk(name, "content", compressed.length);
  vi.stubGlobal("fetch", vi.fn(async () => new Response(compressed)));

  await downloadChunksOnly([asset("game.bin", "md5", [entry])], cache, new DownloadControl(), () => undefined, () => undefined);

  expect(existsSync(join(cache, name))).toBe(true);
  vi.unstubAllGlobals();
});

test("完成标记绑定清单摘要和真实缓存", async () => {
  const root = mkdtempSync(join(tmpdir(), "predownload-status-")), cache = join(root, "cache");
  const content = Buffer.from("123"), prefix = (await xxhash()).h64Raw(content).toString(16).padStart(16, "0");
  const entry = chunk(`${prefix}_chunk`, "x", content.length);
  const build = normalizeBuild({ version: "6.7.0", assets: [asset("game.bin", "md5", [entry])] });
  mkdirSync(cache);
  writeFileSync(join(cache, entry.name), content);
  writePredownloadStatus(cache, { tag: build.version, manifest_digest: predownloadDigest(build), finished: true, total_chunks: 1 });
  expect((await readPredownloadStatus(cache, build))?.finished).toBe(true);
  writeFileSync(join(cache, entry.name), "456"); expect(await readPredownloadStatus(cache, build)).toBeNull();
  expect(existsSync(cache)).toBe(false);
});

test("正式更新可复用预下载的有效缓存交集", async () => {
  const root = mkdtempSync(join(tmpdir(), "predownload-reuse-")), cache = join(root, "cache");
  const content = Buffer.from("cached"), prefix = (await xxhash()).h64Raw(content).toString(16).padStart(16, "0");
  const cached = chunk(`${prefix}_cached`, "cached", content.length), missing = chunk("missing", "missing", 7);
  const predownload = normalizeBuild({ version: "6.8.0", kind: "predownload_diff", assets: [asset("game.bin", "md5", [cached])] });
  const update = normalizeBuild({ version: "6.8.0", kind: "version_diff_chunks", assets: [asset("game.bin", "md5", [cached])] });
  const largerUpdate = normalizeBuild({ version: "6.8.0", kind: "version_diff_chunks", assets: [asset("game.bin", "md5", [cached, missing])] });
  mkdirSync(cache);
  writeFileSync(join(cache, cached.name), content);

  expect(predownloadDigest(predownload)).toBe(predownloadDigest(update));
  expect(await predownloadCachedBytes(cache, largerUpdate)).toBe(content.length);
});

test("预下载拒绝缓存分片符号链接", async () => {
  const root = mkdtempSync(join(tmpdir(), "predownload-link-")), cache = join(root, "cache"), victim = join(root, "victim");
  const content = Buffer.from("protected"), packed = zstdCompressSync(content);
  const prefix = (await xxhash()).h64Raw(packed).toString(16).padStart(16, "0"), entry = chunk(`${prefix}_linked`, "protected", packed.length);
  mkdirSync(cache); writeFileSync(victim, "private"); symlinkSync(victim, join(cache, `${entry.name}.part`));
  vi.stubGlobal("fetch", vi.fn(async () => new Response(packed)));

  await expect(downloadChunksOnly([asset("game.bin", "md5", [entry])], cache, new DownloadControl(), () => undefined, () => undefined)).rejects.toThrow("路径包含链接");
  expect(readFileSync(victim, "utf8")).toBe("private");
  vi.unstubAllGlobals();
});

function asset(name: string, md5: string, chunks: SophonChunk[]): GameAsset {
  return { name, size: chunks.reduce((total, value) => total + value.decompressed_size, 0), md5, chunks };
}

function chunk(name: string, content: string, size = 1): SophonChunk {
  return { name, decompressed_md5: createHash("md5").update(content).digest("hex"), offset: 0, size, decompressed_size: content.length, url: "https://fixture/chunk" };
}
