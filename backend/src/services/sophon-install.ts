import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync, openSync, closeSync, writeSync } from "node:fs";
import { join } from "node:path";
import { zstdDecompressSync } from "node:zlib";
import xxhash from "xxhash-wasm";
import { AppError } from "../core/errors";
import type { GameAsset, SophonChunk } from "../providers/provider";
import { DownloadControl } from "./download";
import { ensureParent, safeTarget } from "./installer";

export async function installSophon(
  assets: GameAsset[], staging: string, cache: string, control: DownloadControl,
  progress: (bytes: number) => void, chunkProgress: (name: string, done: number, total: number) => void,
): Promise<void> {
  mkdirSync(cache, { recursive: true });
  for (const asset of assets) {
    await control.checkpoint(); const target = safeTarget(staging, asset.name);
    if (existsSync(target) && md5(target) === asset.md5.toLowerCase()) { for (const chunk of asset.chunks) { progress(chunk.size); chunkProgress(chunk.name, chunk.size, chunk.size); } continue; }
    const chunks = await Promise.all(asset.chunks.map((chunk) => getChunk(chunk, cache, control, progress, chunkProgress)));
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
    for (const path of chunks) rmSync(path, { force: true });
  }
}

async function getChunk(chunk: SophonChunk, cache: string, control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void): Promise<string> {
  const path = join(cache, chunk.name); if (existsSync(path) && await xxh(path, chunk.name)) { progress(chunk.size); report(chunk.name, chunk.size, chunk.size); return path; }
  const partial = `${path}.part`; let offset = existsSync(partial) ? statSync(partial).size : 0;
  if (offset > chunk.size) { rmSync(partial); offset = 0; }
  const response = await fetch(chunk.url, { headers: offset ? { Range: `bytes=${offset}-` } : {} });
  if (offset && response.status !== 206) { rmSync(partial, { force: true }); return getChunk(chunk, cache, control, progress, report); }
  if (!response.ok || !response.body) throw new AppError("sophon_download_failed", `${chunk.name} 下载失败`, 502);
  const reader = response.body.getReader(); const blocks: Uint8Array[] = offset ? [readFileSync(partial)] : [];
  while (true) { const value = await reader.read(); if (value.done) break; await control.checkpoint(); blocks.push(value.value); offset += value.value.length; progress(value.value.length); report(chunk.name, offset, chunk.size); }
  writeFileSync(partial, Buffer.concat(blocks)); if (offset !== chunk.size || !await xxh(partial, chunk.name)) { rmSync(partial); throw new AppError("sophon_chunk_invalid", `${chunk.name} 分块校验失败`); }
  renameSync(partial, path); return path;
}

async function xxh(path: string, name: string): Promise<boolean> { return (await xxhash()).h64Raw(readFileSync(path)).toString(16).padStart(16, "0") === name.split("_", 1)[0]?.toLowerCase(); }
function md5(path: string): string { return createHash("md5").update(readFileSync(path)).digest("hex"); }
