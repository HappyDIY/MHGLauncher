import { existsSync, mkdirSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import { AppError } from "../core/errors";
import type { GameAsset, SophonChunk, GamePatchAsset } from "../providers/provider";
import { DownloadControl } from "./download";
import { streamDownload } from "./download-transfer";
import type { TokenBucketRateLimiter } from "./rate-limiter";
import { xxhash64File } from "./file-hash";
import { safeIdentifier } from "../core/safe-path";
import { concurrentMap } from "./concurrent-map";

export async function downloadChunksOnly(
  assets: GameAsset[], cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void,
  workers = 4, rateLimiter?: TokenBucketRateLimiter | null,
): Promise<void> {
  mkdirSync(cache, { recursive: true });
  for (const asset of assets) {
    await control.checkpoint();
    await concurrentMap(asset.chunks, workers, control, (chunk) => getChunkOnly(chunk, cache, control, progress, chunkProgress, rateLimiter));
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
    const patchId = safeIdentifier(patchAsset.patch.id, "补丁标识"), path = join(cache, patchId);
    if (existsSync(path) && await xxh(path, patchId)) {
      progress(patchAsset.patch.file_size); chunkProgress(patchId, patchAsset.patch.file_size, patchAsset.patch.file_size); continue;
    }
    chunkProgress(patchAsset.patch.id, 0, patchAsset.patch.file_size);
    await streamDownload(patchAsset.patch.url, `${path}.part`, patchAsset.patch.file_size, patchAsset.patch.id, control, progress, (done) => chunkProgress(patchAsset.patch.id, done, patchAsset.patch.file_size), rateLimiter);
    if (!await xxh(`${path}.part`, patchId)) {
      progress(-patchAsset.patch.file_size); rmSync(`${path}.part`, { force: true });
      throw new AppError("sophon_patch_invalid", `${patchId} 预下载补丁校验失败`);
    }
    renameSync(`${path}.part`, path); chunkProgress(patchAsset.patch.id, patchAsset.patch.file_size, patchAsset.patch.file_size);
  }
}

async function getChunkOnly(chunk: SophonChunk, cache: string, control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void, rateLimiter?: TokenBucketRateLimiter | null): Promise<string> {
  const name = safeIdentifier(chunk.name, "分块标识"), path = join(cache, name); if (existsSync(path) && await xxh(path, name)) { progress(chunk.size); report(name, chunk.size, chunk.size); return path; }
  const partial = `${path}.part`;
  await streamDownload(chunk.url, partial, chunk.size, chunk.name, control, progress, (done) => report(chunk.name, done, chunk.size), rateLimiter);
  if (!await xxh(partial, chunk.name)) { progress(-chunk.size); rmSync(partial); throw new AppError("sophon_chunk_invalid", `${chunk.name} 分块校验失败`); }
  renameSync(partial, path); return path;
}

async function xxh(path: string, name: string): Promise<boolean> {
  return await xxhash64File(path) === name.split("_", 1)[0]?.toLowerCase();
}
