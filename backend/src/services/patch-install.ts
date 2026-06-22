import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import xxhash from "xxhash-wasm";
import { AppError } from "../core/errors";
import type { GamePatchAsset, SophonPatch } from "../providers/provider";
import { DownloadControl } from "./download";
import { ensureParent, safeTarget } from "./installer";

export async function installPatches(
  assets: GamePatchAsset[], staging: string, cache: string, control: DownloadControl,
  progress: (bytes: number) => void, report: (name: string, done: number, total: number) => void,
): Promise<void> {
  mkdirSync(cache, { recursive: true }); const patches = new Map(assets.map(({ patch }) => [patch.id, patch]));
  const paths = new Map<string, string>();
  for (const patch of patches.values()) paths.set(patch.id, await getPatch(patch, cache, control, progress, report));
  for (const asset of assets) { await control.checkpoint(); apply(asset, paths.get(asset.patch.id) ?? "", staging); }
}

async function getPatch(patch: SophonPatch, cache: string, control: DownloadControl, progress: (n: number) => void, report: (name: string, done: number, total: number) => void): Promise<string> {
  const path = join(cache, patch.id); if (existsSync(path) && await valid(path, patch)) { progress(patch.file_size); report(patch.id, patch.file_size, patch.file_size); return path; }
  const partial = `${path}.part`; let offset = existsSync(partial) ? statSync(partial).size : 0;
  if (offset > patch.file_size) { rmSync(partial); offset = 0; }
  let response = await fetch(patch.url, { headers: offset ? { Range: `bytes=${offset}-` } : {} });
  if (offset && response.status !== 206) { rmSync(partial, { force: true }); offset = 0; response = await fetch(patch.url); }
  if (!response.ok || !response.body) throw new AppError("sophon_patch_download_failed", `${patch.id} 下载失败`, 502);
  const blocks: Uint8Array[] = offset ? [readFileSync(partial)] : [], reader = response.body.getReader();
  while (true) { const value = await reader.read(); if (value.done) break; await control.checkpoint(); blocks.push(value.value); offset += value.value.length; progress(value.value.length); report(patch.id, offset, patch.file_size); }
  writeFileSync(partial, Buffer.concat(blocks)); if (!await valid(partial, patch)) { rmSync(partial); throw new AppError("sophon_patch_invalid", `${patch.id} 增量补丁校验失败`); }
  renameSync(partial, path); return path;
}

function apply(asset: GamePatchAsset, source: string, staging: string): void {
  const target = safeTarget(staging, asset.name); ensureParent(target);
  const bytes = readFileSync(source).subarray(asset.patch.start, asset.patch.start + asset.patch.length), segment = `${source}.${asset.patch.start}.segment`;
  writeFileSync(segment, bytes);
  try {
    if (asset.patch.original_name) {
      if (!existsSync(target)) throw new AppError("sophon_patch_source_missing", `${asset.name} 缺少原始文件`);
      const output = `${target}.patched`; rmSync(output, { force: true }); const tool = process.env.MHG_HPATCHZ ?? join(process.cwd(), "hpatchz");
      const result = spawnSync(tool, [target, segment, output]);
      if (result.status !== 0 || !existsSync(output) || statSync(output).size !== asset.size) { rmSync(output, { force: true }); throw new AppError("sophon_patch_apply_failed", `${asset.name} 增量补丁应用失败`); }
      renameSync(output, target);
    } else renameSync(segment, target);
    if (createHash("md5").update(readFileSync(target)).digest("hex") !== asset.md5.toLowerCase()) { rmSync(target); throw new AppError("sophon_patch_result_invalid", `${asset.name} 增量更新校验失败`); }
  } finally { rmSync(segment, { force: true }); }
}

async function valid(path: string, patch: SophonPatch): Promise<boolean> {
  if (!existsSync(path) || statSync(path).size !== patch.file_size) return false;
  return (await xxhash()).h64Raw(readFileSync(path)).toString(16).padStart(16, "0") === patch.id.split("_", 1)[0]?.toLowerCase();
}
