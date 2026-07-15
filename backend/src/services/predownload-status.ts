import { existsSync, readFileSync, rmSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import type { PredownloadStatus } from "../core/models";
import type { GameBuild } from "../providers/provider";
import { safeIdentifier } from "../core/safe-path";
import { xxhash64File } from "./file-hash";
import { operationChunks } from "./game-build";
import { managedPath, writeManagedFile } from "./managed-file";

const STATUS_FILENAME = ".mhg-predownload-status.json";

export async function readPredownloadStatus(cacheDir: string, build?: GameBuild, verifyContent = true): Promise<PredownloadStatus | null> {
  const path = managedPath(cacheDir, STATUS_FILENAME);
  if (!existsSync(path)) return null;
  try {
    const value = JSON.parse(readFileSync(path, "utf8")) as PredownloadStatus;
    if (!valid(value, Boolean(build))) return discard(cacheDir);
    if (!build) return value;
    if (!value.finished) return null;
    if (value.tag !== build.version || value.manifest_digest !== predownloadDigest(build)) return discard(cacheDir);
    for (const item of cacheFiles(build)) {
      const target = managedPath(cacheDir, safeIdentifier(item.name, "预下载缓存标识"));
      if (!existsSync(target)) return discard(cacheDir);
      const stat = statSync(target);
      if (!stat.isFile() || stat.size !== item.size || (verifyContent
        && await xxhash64File(target) !== item.name.split("_", 1)[0]?.toLowerCase())) return discard(cacheDir);
    }
    return value;
  } catch { return discard(cacheDir); }
}

export function predownloadDigest(build: GameBuild): string {
  const files = cacheFiles(build).toSorted((left, right) => left.name.localeCompare(right.name));
  return createHash("sha256").update(JSON.stringify({ version: build.version, files })).digest("hex");
}

function cacheFiles(build: GameBuild): Array<{ name: string; size: number }> {
  if (build.patch_assets.length) return [...new Map(build.patch_assets.map(({ patch }) => [patch.id, { name: patch.id, size: patch.file_size }])).values()];
  return [...new Map(build.assets.flatMap(operationChunks).map(({ name, size }) => [name, { name, size }])).values()];
}

export async function predownloadCachedBytes(cacheDir: string, build: GameBuild): Promise<number> {
  let total = 0;
  for (const item of cacheFiles(build)) {
    const target = managedPath(cacheDir, safeIdentifier(item.name, "预下载缓存标识"));
    if (!existsSync(target)) continue;
    const stat = statSync(target);
    if (stat.isFile() && stat.size === item.size
      && await xxhash64File(target) === item.name.split("_", 1)[0]?.toLowerCase()) total += item.size;
  }
  return total;
}

export function writePredownloadStatus(cacheDir: string, status: PredownloadStatus): void {
  writeManagedFile(cacheDir, STATUS_FILENAME, JSON.stringify(status));
}

export function clearPredownloadStatus(cacheDir: string): void {
  rmSync(managedPath(cacheDir, STATUS_FILENAME), { force: true });
}

function discard(cacheDir: string): null {
  rmSync(cacheDir, { recursive: true, force: true });
  return null;
}

function valid(value: PredownloadStatus, requireDigest: boolean): boolean {
  return typeof value.tag === "string" && Boolean(value.tag) && typeof value.manifest_digest === "string"
    && (!requireDigest || /^[a-f0-9]{64}$/i.test(value.manifest_digest)) && typeof value.finished === "boolean"
    && Number.isInteger(value.total_chunks) && value.total_chunks >= 0;
}
