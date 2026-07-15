import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, openSync, closeSync, writeSync } from "node:fs";
import { zstdDecompressSync } from "node:zlib";
import { AppError } from "../core/errors";
import type { GameAsset, SophonChunk } from "../providers/provider";
import { DownloadControl } from "./download";
import { streamDownload } from "./download-transfer";
import { ensureParent, safeTarget } from "./installer";
import { preallocateFileDescriptor } from "./file-allocation";
import type { TokenBucketRateLimiter } from "./rate-limiter";
import { copyRangeToDescriptorSync, hashFile, xxhash64File } from "./file-hash";
import { safeIdentifier } from "../core/safe-path";
import { concurrentMap } from "./concurrent-map";
import { operationChunks } from "./game-build";
import { managedPath } from "./managed-file";

export async function installSophon(
  assets: GameAsset[], staging: string, cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void, workers = 4,
  rateLimiter?: TokenBucketRateLimiter | null, baseAssets: GameAsset[] = [],
  reserveFallback: (chunks: SophonChunk[]) => void = () => undefined,
): Promise<void> {
  mkdirSync(cache, { recursive: true });
  const references = chunkReferences(assets), pending = new Map<string, Promise<string>>();
  const bases = new Map(baseAssets.map((asset) => [asset.name.toLowerCase(), asset]));
  for (const asset of assets) {
    await control.checkpoint(); const target = safeTarget(staging, asset.name);
    if (existsSync(target) && await hashFile(target, "md5", hashOptions(control)) === asset.md5.toLowerCase()) {
      for (const chunk of operationChunks(asset)) { progress(chunk.size); chunkProgress(chunk.name, chunk.size, chunk.size); }
      releaseChunks(asset.chunks, cache, references); continue;
    }
    await installAsset(
      asset, bases.get(asset.name.toLowerCase()), target, cache, control, progress,
      chunkProgress, workers, rateLimiter, pending, reserveFallback,
    );
    releaseChunks(asset.chunks, cache, references);
  }
}

async function installAsset(
  asset: GameAsset, base: GameAsset | undefined, target: string, cache: string, control: DownloadControl,
  progress: (n: number) => void, report: (name: string, done: number, total: number) => void,
  workers: number, limiter: TokenBucketRateLimiter | null | undefined, pending: Map<string, Promise<string>>,
  reserveFallback: (chunks: SophonChunk[]) => void,
): Promise<void> {
  const requested = reusable(asset, base, target) ? operationChunks(asset) : asset.chunks;
  try { await buildAsset(asset, base, target, requested, cache, control, progress, report, workers, limiter, pending); }
  catch (error) {
    if (requested === asset.chunks || error instanceof DOMException && error.name === "AbortError") throw error;
    const prior = new Set(requested.map(({ name }) => name));
    reserveFallback(asset.chunks.filter(({ name }) => !prior.has(name)));
    await buildAsset(asset, undefined, target, asset.chunks, cache, control, progress, report, workers, limiter, pending);
  }
}

async function buildAsset(
  asset: GameAsset, base: GameAsset | undefined, target: string, requested: SophonChunk[], cache: string,
  control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void,
  workers: number, limiter: TokenBucketRateLimiter | null | undefined, pending: Map<string, Promise<string>>,
): Promise<void> {
  const downloaded = await concurrentMap(requested, workers, control, (chunk) => sharedChunk(
    chunk, pending, () => getChunk(chunk, cache, control, progress, report, limiter),
  ));
  const paths = new Map(requested.map((chunk, index) => [chunk.name, downloaded[index] as string]));
  const old = new Map(base?.chunks.map((chunk) => [chunk.decompressed_md5.toLowerCase(), chunk]) ?? []);
  ensureParent(target); const temporary = `${target}.${process.pid}.mhg-installing`; rmSync(temporary, { force: true });
  try {
    const descriptor = openSync(temporary, "w"); preallocateFileDescriptor(descriptor, asset.size);
    try {
      for (const chunk of asset.chunks) {
        const path = paths.get(chunk.name);
        if (path) writeBuffer(descriptor, decodeChunk(path, chunk, pending), chunk.offset);
        else {
          const source = old.get(chunk.decompressed_md5.toLowerCase());
          if (!source) throw new AppError("sophon_diff_source_missing", `${asset.name} 缺少可复用分块`);
          copyRangeToDescriptorSync(target, descriptor, source.offset, chunk.offset, chunk.decompressed_size);
        }
      }
    } finally { closeSync(descriptor); }
    if (statSync(temporary).size !== asset.size || await hashFile(temporary, "md5", hashOptions(control)) !== asset.md5.toLowerCase()) {
      throw new AppError("sophon_asset_invalid", `${asset.name} 文件校验失败`);
    }
    renameSync(temporary, target);
  } catch (error) { rmSync(temporary, { force: true }); throw error; }
}

function reusable(asset: GameAsset, base: GameAsset | undefined, target: string): boolean {
  if (asset.required_chunks === undefined || !base || !existsSync(target)) return false;
  const required = new Set(asset.required_chunks.map((chunk) => chunk.decompressed_md5.toLowerCase()));
  const old = new Map(base.chunks.map((chunk) => [chunk.decompressed_md5.toLowerCase(), chunk]));
  return asset.chunks.every((chunk) => required.has(chunk.decompressed_md5.toLowerCase())
    || old.get(chunk.decompressed_md5.toLowerCase())?.decompressed_size === chunk.decompressed_size);
}

function decodeChunk(path: string, chunk: SophonChunk, pending: Map<string, Promise<string>>): Buffer {
  try {
    const decoded = zstdDecompressSync(readFileSync(path), { maxOutputLength: chunk.decompressed_size });
    if (decoded.length !== chunk.decompressed_size
      || createHash("md5").update(decoded).digest("hex") !== chunk.decompressed_md5.toLowerCase()) throw new Error();
    return decoded;
  } catch {
    rmSync(path, { force: true }); pending.delete(chunk.name);
    throw new AppError("sophon_chunk_content_invalid", `${chunk.name} 内容校验失败`);
  }
}

function writeBuffer(descriptor: number, buffer: Buffer, offset: number): void {
  let written = 0;
  while (written < buffer.length) written += writeSync(
    descriptor, buffer, written, buffer.length - written, offset + written,
  );
}

function sharedChunk(chunk: SophonChunk, pending: Map<string, Promise<string>>, create: () => Promise<string>): Promise<string> {
  const current = pending.get(chunk.name); if (current) return current;
  const task = create().catch((error) => { pending.delete(chunk.name); throw error; });
  pending.set(chunk.name, task); return task;
}

async function getChunk(chunk: SophonChunk, cache: string, control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void, rateLimiter?: TokenBucketRateLimiter | null): Promise<string> {
  const name = safeIdentifier(chunk.name, "分块标识"), path = managedPath(cache, name); if (existsSync(path) && await xxh(path, name)) { progress(chunk.size); report(name, chunk.size, chunk.size); return path; }
  const partial = managedPath(cache, `${name}.part`);
  await streamDownload(chunk.url, partial, chunk.size, chunk.name, control, progress, (done) => report(chunk.name, done, chunk.size), rateLimiter);
  if (!await xxh(partial, chunk.name)) { progress(-chunk.size); rmSync(partial); throw new AppError("sophon_chunk_invalid", `${chunk.name} 分块校验失败`); }
  renameSync(partial, path); return path;
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
    else { references.delete(chunk.name); rmSync(managedPath(cache, chunk.name), { force: true }); }
  }
}

async function xxh(path: string, name: string): Promise<boolean> {
  return await xxhash64File(path) === name.split("_", 1)[0]?.toLowerCase();
}

function hashOptions(control: DownloadControl): { signal: AbortSignal; checkpoint: () => Promise<void> } {
  return { signal: control.signal, checkpoint: () => control.checkpoint() };
}
