import { statfsSync } from "node:fs";
import { dirname, resolve } from "node:path";

export interface DiskSpaceInfo { available: number; required: number; sufficient: boolean }

const SPACE_BUFFER_BYTES = 1024 * 1024 * 1024;

function queryAvailable(path: string): number {
  let current = resolve(path);
  while (true) {
    try {
      const stats = statfsSync(current);
      return stats.bavail * stats.bsize;
    } catch {
      const parent = dirname(current);
      if (parent === current) return 0;
      current = parent;
    }
  }
}

export function diskSpaceInfo(path: string, installBytes: number, alreadyDownloadedBytes = 0): DiskSpaceInfo {
  const required = Math.max(0, installBytes - alreadyDownloadedBytes) + SPACE_BUFFER_BYTES;
  const free = queryAvailable(path);
  return { available: free, required, sufficient: free >= required };
}
