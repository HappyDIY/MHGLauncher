import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { GameAsset, GameBuild } from "../providers/provider";
import { safeTarget } from "./installer";

interface IntegrityEntry { md5: string; size: number; mtime_ns: string }
interface IntegrityIndex { version: 1; assets: Record<string, IntegrityEntry> }
const INDEX_NAME = ".mhg-integrity.json";

export function writeIntegrityIndex(root: string, build: GameBuild): void {
  const index = readIndex(root) ?? { version: 1, assets: {} };
  for (const asset of build.assets) record(index, root, asset.name, asset.md5, asset.size);
  for (const asset of build.patch_assets) record(index, root, asset.name, asset.md5, asset.size);
  for (const name of build.deprecated_files) delete index.assets[normalize(name)];
  writeFileSync(join(root, INDEX_NAME), JSON.stringify(index));
}

export function selectInvalidAssets(root: string, assets: GameAsset[]): GameAsset[] {
  const index = readIndex(root), packageHashes = readPackageHashes(root);
  return assets.filter((asset) => !fastValid(root, asset, index, packageHashes));
}

function fastValid(
  root: string, asset: GameAsset, index: IntegrityIndex | null, packageHashes: Map<string, string>,
): boolean {
  const name = normalize(asset.name), path = safeTarget(root, name);
  if (!existsSync(path)) return false;
  const stat = statSync(path, { bigint: true });
  if (!stat.isFile() || stat.size !== BigInt(asset.size)) return false;
  const expected = asset.md5.toLowerCase(), saved = index?.assets[name];
  if (saved) return saved.md5 === expected && saved.size === asset.size && saved.mtime_ns === stat.mtimeNs.toString();
  return packageHashes.get(name) === expected;
}

function record(index: IntegrityIndex, root: string, name: string, md5: string, size: number): void {
  const normalized = normalize(name), stat = statSync(safeTarget(root, normalized), { bigint: true });
  index.assets[normalized] = { md5: md5.toLowerCase(), size, mtime_ns: stat.mtimeNs.toString() };
}

function readIndex(root: string): IntegrityIndex | null {
  try {
    const value = JSON.parse(readFileSync(join(root, INDEX_NAME), "utf8")) as IntegrityIndex;
    return value.version === 1 && value.assets && typeof value.assets === "object" ? value : null;
  } catch { return null; }
}

function readPackageHashes(root: string): Map<string, string> {
  const result = new Map<string, string>();
  for (const name of ["pkg_version", "Audio_Chinese_pkg_version", "Audio_English(US)_pkg_version", "Audio_Japanese_pkg_version", "Audio_Korean_pkg_version"]) {
    const path = join(root, name); if (!existsSync(path)) continue;
    for (const line of readFileSync(path, "utf8").split("\n")) {
      try {
        const value = JSON.parse(line) as { remoteName?: string; md5?: string };
        if (value.remoteName && value.md5) result.set(normalize(value.remoteName), value.md5.toLowerCase());
      } catch { /* 忽略损坏的单行，缺失项会进入修复流程 */ }
    }
  }
  return result;
}

function normalize(name: string): string { return name.replaceAll("\\", "/"); }
