import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, openSync, closeSync, writeSync } from "node:fs";
import { join } from "node:path";
import { zstdDecompressSync } from "node:zlib";
import xxhash from "xxhash-wasm";
import { AppError } from "../core/errors";
import type { GameAsset, SophonChunk } from "../providers/provider";
import { DownloadControl } from "./download";
import { streamDownload } from "./download-transfer";
import { ensureParent, safeTarget } from "./installer";

export async function installSophon(
  assets: GameAsset[], staging: string, cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void, workers = 4,
): Promise<void> {
  mkdirSync(cache, { recursive: true });
  for (const asset of assets) {
    await control.checkpoint(); const target = safeTarget(staging, asset.name);
    if (existsSync(target) && md5(target) === asset.md5.toLowerCase()) { for (const chunk of asset.chunks) { progress(chunk.size); chunkProgress(chunk.name, chunk.size, chunk.size); } continue; }
    const chunks = await concurrentMap(asset.chunks, workers, (chunk) => getChunk(chunk, cache, control, progress, chunkProgress));
    ensureParent(target); const descriptor = openSync(target, "w");
    try {
      for (let index = 0; index < chunks.length; index += 1) {
        const chunk = asset.chunks[index], path = chunks[index]; if (!chunk || !path) continue;
        const decoded = zstdDecompressSync(readFileSync(path));
        if (decoded.length !== chunk.decompressed_size || createHash("md5").update(decoded).digest("hex") !== chunk.decompressed_md5.toLowerCase()) throw new AppError("sophon_chunk_content_invalid", `${chunk.name} 内容校验失败`);
        writeSync(descriptor, decoded, 0, decoded.length, chunk.offset);
      }
    } finally { closeSync(descriptor); }
    if (statSync(target).size !== asset.size || md5(target) !== asset.md5.toLowerCase()) { rmSync(target); throw new AppError("sophon_asset_invalid", `${asset.name} 文件校验失败`); }
  }
}

async function getChunk(chunk: SophonChunk, cache: string, control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void): Promise<string> {
  const path = join(cache, chunk.name); if (existsSync(path) && await xxh(path, chunk.name)) { progress(chunk.size); report(chunk.name, chunk.size, chunk.size); return path; }
  const partial = `${path}.part`;
  await streamDownload(chunk.url, partial, chunk.size, chunk.name, control, progress, (done) => report(chunk.name, done, chunk.size));
  if (!await xxh(partial, chunk.name)) { progress(-chunk.size); rmSync(partial); throw new AppError("sophon_chunk_invalid", `${chunk.name} 分块校验失败`); }
  renameSync(partial, path); return path;
}

async function concurrentMap<T, R>(items: T[], limit: number, task: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length); let next = 0;
  async function worker(): Promise<void> {
    while (next < items.length) { const index = next++; const item = items[index]; if (item) results[index] = await task(item); }
  }
  await Promise.all(Array.from({ length: Math.min(Math.max(limit, 1), items.length) }, worker));
  return results;
}

async function xxh(path: string, name: string): Promise<boolean> { return (await xxhash()).h64Raw(readFileSync(path)).toString(16).padStart(16, "0") === name.split("_", 1)[0]?.toLowerCase(); }
function md5(path: string): string { return createHash("md5").update(readFileSync(path)).digest("hex"); }
