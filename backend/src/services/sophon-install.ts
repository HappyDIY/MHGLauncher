import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, openSync, closeSync, writeSync } from "node:fs";
import { join } from "node:path";
import { zstdDecompressSync } from "node:zlib";
import { AppError } from "../core/errors";
import type { GameAsset, SophonChunk } from "../providers/provider";
import { DownloadControl } from "./download";
import { streamDownload } from "./download-transfer";
import { ensureParent, safeTarget } from "./installer";
import { preallocateFileDescriptor } from "./file-allocation";
import type { TokenBucketRateLimiter } from "./rate-limiter";
import { hashFile, xxhash64File } from "./file-hash";
import { safeIdentifier } from "../core/safe-path";

export async function installSophon(
  assets: GameAsset[], staging: string, cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void, workers = 4,
  rateLimiter?: TokenBucketRateLimiter | null,
): Promise<void> {
  mkdirSync(cache, { recursive: true });
  const references = chunkReferences(assets);
  for (const asset of assets) {
    await control.checkpoint(); const target = safeTarget(staging, asset.name);
    if (existsSync(target) && await hashFile(target, "md5") === asset.md5.toLowerCase()) {
      for (const chunk of asset.chunks) { progress(chunk.size); chunkProgress(chunk.name, chunk.size, chunk.size); }
      releaseChunks(asset.chunks, cache, references); continue;
    }
    const chunks = await concurrentMap(asset.chunks, workers, (chunk) => getChunk(chunk, cache, control, progress, chunkProgress, rateLimiter));
    ensureParent(target); const temporary = `${target}.${process.pid}.mhg-installing`; rmSync(temporary, { force: true });
    try {
      const descriptor = openSync(temporary, "w");
      preallocateFileDescriptor(descriptor, asset.size);
      try {
        for (let index = 0; index < chunks.length; index += 1) {
          const chunk = asset.chunks[index], path = chunks[index]; if (!chunk || !path) continue;
          const decoded = zstdDecompressSync(readFileSync(path));
          if (decoded.length !== chunk.decompressed_size || createHash("md5").update(decoded).digest("hex") !== chunk.decompressed_md5.toLowerCase()) throw new AppError("sophon_chunk_content_invalid", `${chunk.name} 内容校验失败`);
          writeSync(descriptor, decoded, 0, decoded.length, chunk.offset);
        }
      } finally { closeSync(descriptor); }
      if (statSync(temporary).size !== asset.size || await hashFile(temporary, "md5") !== asset.md5.toLowerCase()) throw new AppError("sophon_asset_invalid", `${asset.name} 文件校验失败`);
      renameSync(temporary, target);
    } catch (error) { rmSync(temporary, { force: true }); throw error; }
    releaseChunks(asset.chunks, cache, references);
  }
}

async function getChunk(chunk: SophonChunk, cache: string, control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void, rateLimiter?: TokenBucketRateLimiter | null): Promise<string> {
  const name = safeIdentifier(chunk.name, "分块标识"), path = join(cache, name); if (existsSync(path) && await xxh(path, name)) { progress(chunk.size); report(name, chunk.size, chunk.size); return path; }
  const partial = `${path}.part`;
  await streamDownload(chunk.url, partial, chunk.size, chunk.name, control, progress, (done) => report(chunk.name, done, chunk.size), rateLimiter);
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

function chunkReferences(assets: GameAsset[]): Map<string, number> {
  const result = new Map<string, number>();
  for (const chunk of assets.flatMap(({ chunks }) => chunks)) result.set(chunk.name, (result.get(chunk.name) ?? 0) + 1);
  return result;
}

function releaseChunks(chunks: SophonChunk[], cache: string, references: Map<string, number>): void {
  for (const chunk of chunks) {
    const remaining = (references.get(chunk.name) ?? 1) - 1;
    if (remaining > 0) references.set(chunk.name, remaining);
    else { references.delete(chunk.name); rmSync(join(cache, chunk.name), { force: true }); }
  }
}

async function xxh(path: string, name: string): Promise<boolean> {
  return await xxhash64File(path) === name.split("_", 1)[0]?.toLowerCase();
}
