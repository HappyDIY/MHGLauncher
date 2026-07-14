import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { zstdCompressSync } from "node:zlib";
import { expect, test, vi } from "vitest";
import xxhash from "xxhash-wasm";
import type { GameAsset, SophonChunk } from "../src/providers/provider";
import { normalizeBuild } from "../src/providers/provider";
import { checkedPredownloadBuild, diffPredownloadBuild } from "../src/services/predownload-build";
import { downloadChunksOnly } from "../src/services/predownload";
import { DownloadControl } from "../src/services/download";
import { predownloadDigest, readPredownloadStatus, writePredownloadStatus } from "../src/services/predownload-status";

test("预下载只计算本地缺失的差异分块", () => {
  const shared = chunk("shared", "same"), old = chunk("old", "old"), next = chunk("next", "next");
  const local = normalizeBuild({ version: "6.6.0", assets: [asset("data.bin", "old-md5", [shared, old])] });
  const remote = normalizeBuild({ version: "6.7.0", assets: [
    asset("data.bin", "new-md5", [shared, next]), asset("new.bin", "new-file", [chunk("added", "added")]),
  ], is_predownload: true });

  const diff = diffPredownloadBuild(local, remote);

  expect(diff.assets.map((value) => value.name)).toEqual(["data.bin", "new.bin"]);
  expect(diff.assets[0]?.chunks.map((value) => value.name)).toEqual(["next"]);
  expect(diff.assets[1]?.chunks.map((value) => value.name)).toEqual(["added"]);
});

test("预下载要求本机版本与常规通道一致", () => {
  const local = normalizeBuild({ version: "6.7.0" });
  const remote = normalizeBuild({ version: "6.8.0", is_predownload: true });
  expect(() => checkedPredownloadBuild("6.6.0", local, remote)).toThrow("请先完成常规更新或修复");
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

test("完成标记绑定清单摘要和真实缓存", () => {
  const root = mkdtempSync(join(tmpdir(), "predownload-status-")), cache = join(root, "cache"), entry = chunk("abcd_chunk", "x", 3);
  const build = normalizeBuild({ version: "6.7.0", assets: [asset("game.bin", "md5", [entry])] });
  mkdirSync(cache);
  writeFileSync(join(cache, entry.name), "123");
  writePredownloadStatus(cache, { tag: build.version, manifest_digest: predownloadDigest(build), finished: true, total_chunks: 1 });
  expect(readPredownloadStatus(cache, build)?.finished).toBe(true);
  rmSync(join(cache, entry.name)); expect(readPredownloadStatus(cache, build)).toBeNull();
  expect(existsSync(cache)).toBe(false);
});

function asset(name: string, md5: string, chunks: SophonChunk[]): GameAsset {
  return { name, size: chunks.reduce((total, value) => total + value.decompressed_size, 0), md5, chunks };
}

function chunk(name: string, content: string, size = 1): SophonChunk {
  return { name, decompressed_md5: createHash("md5").update(content).digest("hex"), offset: 0, size, decompressed_size: content.length, url: "https://fixture/chunk" };
}
