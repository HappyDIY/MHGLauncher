import { existsSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import type { PredownloadStatus } from "../core/models";

const STATUS_FILENAME = ".mhg-predownload-status.json";

export function readPredownloadStatus(cacheDir: string): PredownloadStatus | null {
  const path = join(cacheDir, STATUS_FILENAME);
  if (!existsSync(path)) return null;
  try { return JSON.parse(readFileSync(path, "utf8")) as PredownloadStatus; } catch { return null; }
}

export function writePredownloadStatus(cacheDir: string, status: PredownloadStatus): void {
  writeFileSync(join(cacheDir, STATUS_FILENAME), JSON.stringify(status));
}

export function clearPredownloadStatus(cacheDir: string): void {
  rmSync(join(cacheDir, STATUS_FILENAME), { force: true });
}