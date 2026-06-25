import { statfsSync } from "node:fs";
import { resolve } from "node:path";

export interface DiskSpaceInfo { available: number; required: number; sufficient: boolean }

const SPACE_BUFFER_BYTES = 1024 * 1024 * 1024;

function queryAvailable(path: string): number {
  try {
    const stats = statfsSync(path);
    return stats.bavail * stats.bsize;
  } catch {
    return 0;
  }
}

export function diskSpaceInfo(path: string, installBytes: number, alreadyDownloadedBytes = 0): DiskSpaceInfo {
  const required = Math.max(0, installBytes - alreadyDownloadedBytes) + SPACE_BUFFER_BYTES;
  const free = queryAvailable(resolve(path));
  return { available: free, required, sufficient: free >= required };
}