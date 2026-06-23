import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
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

function md5(value: Buffer): string { return createHash("md5").update(value).digest("hex"); }
