import { existsSync, mkdirSync, renameSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { AppError } from "../core/errors";
import type { GamePatchAsset, SophonPatch } from "../providers/provider";
import { DownloadControl } from "./download";
import { streamDownload } from "./download-transfer";
import { ensureParent, safeTarget } from "./installer";
import { copyRangeSync, hashFileSync, xxhash64File } from "./file-hash";
import { safeIdentifier } from "../core/safe-path";

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
  const id = safeIdentifier(patch.id, "补丁标识"), path = join(cache, id); if (existsSync(path) && await valid(path, patch)) { progress(patch.file_size); report(id, patch.file_size, patch.file_size); return path; }
  const partial = `${path}.part`;
  await streamDownload(patch.url, partial, patch.file_size, patch.id, control, progress, (done) => report(patch.id, done, patch.file_size));
  if (!await valid(partial, patch)) { progress(-patch.file_size); rmSync(partial); throw new AppError("sophon_patch_invalid", `${patch.id} 增量补丁校验失败`); }
  renameSync(partial, path); return path;
}

function apply(asset: GamePatchAsset, source: string, staging: string): void {
  const target = safeTarget(staging, asset.name); ensureParent(target);
  const segment = `${source}.${asset.patch.start}.segment`;
  copyRangeSync(source, segment, asset.patch.start, asset.patch.length);
  try {
    if (asset.patch.original_name) {
      if (!existsSync(target)) throw new AppError("sophon_patch_source_missing", `${asset.name} 缺少原始文件`);
      const output = `${target}.patched`; rmSync(output, { force: true }); const tool = process.env.MHG_HPATCHZ ?? join(process.cwd(), "hpatchz");
      const result = spawnSync(tool, [target, segment, output]);
      if (result.status !== 0 || !existsSync(output) || statSync(output).size !== asset.size) { rmSync(output, { force: true }); throw new AppError("sophon_patch_apply_failed", `${asset.name} 增量补丁应用失败`); }
      renameSync(output, target);
    } else renameSync(segment, target);
    if (hashFileSync(target, "md5") !== asset.md5.toLowerCase()) { rmSync(target); throw new AppError("sophon_patch_result_invalid", `${asset.name} 增量更新校验失败`); }
  } finally { rmSync(segment, { force: true }); }
}

async function valid(path: string, patch: SophonPatch): Promise<boolean> {
  if (!existsSync(path) || statSync(path).size !== patch.file_size) return false;
  return await xxhash64File(path) === patch.id.split("_", 1)[0]?.toLowerCase();
}
