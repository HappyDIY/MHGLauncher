import { existsSync, mkdirSync, readFileSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import xxhash from "xxhash-wasm";
import { AppError } from "../core/errors";
import type { GameAsset, SophonChunk, GamePatchAsset } from "../providers/provider";
import { DownloadControl } from "./download";
import { streamDownload } from "./download-transfer";
import type { TokenBucketRateLimiter } from "./rate-limiter";

export async function downloadChunksOnly(
  assets: GameAsset[], cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void,
  workers = 4, rateLimiter?: TokenBucketRateLimiter | null,
): Promise<void> {
  mkdirSync(cache, { recursive: true }); const references = chunkReferences(assets);
  for (const asset of assets) {
    await control.checkpoint();
    await concurrentMap(asset.chunks, workers, (chunk) => getChunkOnly(chunk, cache, control, progress, chunkProgress, rateLimiter));
    releaseChunks(asset.chunks, cache, references);
  }
}

export async function downloadPatchesOnly(
  patchAssets: GamePatchAsset[], cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void,
  rateLimiter?: TokenBucketRateLimiter | null,
): Promise<void> {
  mkdirSync(cache, { recursive: true });
  for (const patchAsset of patchAssets) {
    await control.checkpoint();
    const path = join(cache, patchAsset.patch.id);
    chunkProgress(patchAsset.patch.id, 0, patchAsset.patch.file_size);
    await streamDownload(patchAsset.patch.url, `${path}.part`, patchAsset.patch.file_size, patchAsset.patch.id, control, progress, (done) => chunkProgress(patchAsset.patch.id, done, patchAsset.patch.file_size), rateLimiter);
    renameSync(`${path}.part`, path); chunkProgress(patchAsset.patch.id, patchAsset.patch.file_size, patchAsset.patch.file_size);
  }
}

async function getChunkOnly(chunk: SophonChunk, cache: string, control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void, rateLimiter?: TokenBucketRateLimiter | null): Promise<string> {
  const path = join(cache, chunk.name); if (existsSync(path) && await xxh(path, chunk.name)) { progress(chunk.size); report(chunk.name, chunk.size, chunk.size); return path; }
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

async function xxh(path: string, name: string): Promise<boolean> { return (await xxhash()).h64Raw(readFileSync(path)).toString(16).padStart(16, "0") === name.split("_", 1)[0]?.toLowerCase(); }