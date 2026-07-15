import { existsSync, mkdirSync, renameSync, rmSync } from "node:fs";
import { AppError } from "../core/errors";
import type { GameAsset, SophonChunk, GamePatchAsset } from "../providers/provider";
import { DownloadControl } from "./download";
import { streamDownload } from "./download-transfer";
import type { TokenBucketRateLimiter } from "./rate-limiter";
import { xxhash64File } from "./file-hash";
import { safeIdentifier } from "../core/safe-path";
import { concurrentMap } from "./concurrent-map";
import { operationChunks } from "./game-build";
import { managedPath } from "./managed-file";

export async function downloadChunksOnly(
  assets: GameAsset[], cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void,
  workers = 4, rateLimiter?: TokenBucketRateLimiter | null,
): Promise<void> {
  mkdirSync(cache, { recursive: true });
  const pending = new Map<string, Promise<string>>();
  for (const asset of assets) {
    await control.checkpoint();
    await concurrentMap(operationChunks(asset), workers, control, (chunk) => sharedChunk(
      chunk, pending, () => getChunkOnly(chunk, cache, control, progress, chunkProgress, rateLimiter),
    ));
  }
}

function sharedChunk(chunk: SophonChunk, pending: Map<string, Promise<string>>, create: () => Promise<string>): Promise<string> {
  const current = pending.get(chunk.name); if (current) return current;
  const task = create().catch((error) => { pending.delete(chunk.name); throw error; });
  pending.set(chunk.name, task); return task;
}

export async function downloadPatchesOnly(
  patchAssets: GamePatchAsset[], cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void,
  rateLimiter?: TokenBucketRateLimiter | null,
): Promise<void> {
  mkdirSync(cache, { recursive: true });
  for (const patchAsset of new Map(patchAssets.map((asset) => [asset.patch.id, asset])).values()) {
    await control.checkpoint();
    const patchId = safeIdentifier(patchAsset.patch.id, "补丁标识"), path = managedPath(cache, patchId);
    if (existsSync(path) && await xxh(path, patchId)) {
      progress(patchAsset.patch.file_size); chunkProgress(patchId, patchAsset.patch.file_size, patchAsset.patch.file_size); continue;
    }
    chunkProgress(patchAsset.patch.id, 0, patchAsset.patch.file_size);
    const partial = managedPath(cache, `${patchId}.part`);
    await streamDownload(patchAsset.patch.url, partial, patchAsset.patch.file_size, patchAsset.patch.id, control, progress, (done) => chunkProgress(patchAsset.patch.id, done, patchAsset.patch.file_size), rateLimiter);
    if (!await xxh(partial, patchId)) {
      progress(-patchAsset.patch.file_size); rmSync(partial, { force: true });
      throw new AppError("sophon_patch_invalid", `${patchId} 预下载补丁校验失败`);
    }
    renameSync(partial, path); chunkProgress(patchAsset.patch.id, patchAsset.patch.file_size, patchAsset.patch.file_size);
  }
}

async function getChunkOnly(chunk: SophonChunk, cache: string, control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void, rateLimiter?: TokenBucketRateLimiter | null): Promise<string> {
  const name = safeIdentifier(chunk.name, "分块标识"), path = managedPath(cache, name); if (existsSync(path) && await xxh(path, name)) { progress(chunk.size); report(name, chunk.size, chunk.size); return path; }
  const partial = managedPath(cache, `${name}.part`);
  await streamDownload(chunk.url, partial, chunk.size, chunk.name, control, progress, (done) => report(chunk.name, done, chunk.size), rateLimiter);
  if (!await xxh(partial, chunk.name)) { progress(-chunk.size); rmSync(partial); throw new AppError("sophon_chunk_invalid", `${chunk.name} 分块校验失败`); }
  renameSync(partial, path); return path;
}

async function xxh(path: string, name: string): Promise<boolean> {
  return await xxhash64File(path) === name.split("_", 1)[0]?.toLowerCase();
}
