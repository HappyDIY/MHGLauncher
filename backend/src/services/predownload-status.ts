import { existsSync, readFileSync, writeFileSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";
import type { PredownloadStatus } from "../core/models";
import type { GameBuild } from "../providers/provider";
import { safeIdentifier } from "../core/safe-path";

const STATUS_FILENAME = ".mhg-predownload-status.json";

export function readPredownloadStatus(cacheDir: string, build?: GameBuild): PredownloadStatus | null {
  const path = join(cacheDir, STATUS_FILENAME);
  if (!existsSync(path)) return null;
  try {
    const value = JSON.parse(readFileSync(path, "utf8")) as PredownloadStatus;
    if (!value.finished || !build || value.tag !== build.version || value.manifest_digest !== predownloadDigest(build)) return build ? null : value;
    for (const item of cacheFiles(build)) {
      const target = join(cacheDir, safeIdentifier(item.name, "预下载缓存标识"));
      if (!existsSync(target) || !statSync(target).isFile() || statSync(target).size !== item.size) return null;
    }
    return value;
  } catch { return null; }
}

export function predownloadDigest(build: GameBuild): string {
  const files = cacheFiles(build).toSorted((left, right) => left.name.localeCompare(right.name));
  return createHash("sha256").update(JSON.stringify({ version: build.version, kind: build.kind, files })).digest("hex");
}

function cacheFiles(build: GameBuild): Array<{ name: string; size: number }> {
  if (build.patch_assets.length) return [...new Map(build.patch_assets.map(({ patch }) => [patch.id, { name: patch.id, size: patch.file_size }])).values()];
  return [...new Map(build.assets.flatMap(({ chunks }) => chunks).map(({ name, size }) => [name, { name, size }])).values()];
}

export function predownloadCachedBytes(cacheDir: string, build: GameBuild): number {
  return readPredownloadStatus(cacheDir, build) ? cacheFiles(build).reduce((total, item) => total + item.size, 0) : 0;
}

export function writePredownloadStatus(cacheDir: string, status: PredownloadStatus): void {
  writeFileSync(join(cacheDir, STATUS_FILENAME), JSON.stringify(status));
}

export function clearPredownloadStatus(cacheDir: string): void {
  rmSync(join(cacheDir, STATUS_FILENAME), { force: true });
}
