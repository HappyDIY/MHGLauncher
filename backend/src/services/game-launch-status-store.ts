import { chmodSync, closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { GameLaunch } from "../core/models";
import { containedPath, safeIdentifier } from "../core/safe-path";

export function loadLaunchStatuses(dataDir: string): GameLaunch[] {
  const root = join(dataDir, "launches"); if (!existsSync(root)) return [];
  const result: GameLaunch[] = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    try {
      const value = JSON.parse(readFileSync(join(root, entry.name, "status.json"), "utf8")) as GameLaunch;
      if (value.id === entry.name && typeof value.status === "string" && Array.isArray(value.logs)) result.push(value);
    } catch { /* 损坏的单个会话不会阻止其他恢复。 */ }
  }
  return result;
}

export function persistLaunchStatus(dataDir: string, launch: GameLaunch): string {
  const payload = JSON.stringify(launch), directory = join(dataDir, "launches", launch.id);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const target = join(directory, "status.json"), temp = `${target}.${process.pid}.tmp`;
  writeFileSync(temp, payload, { mode: 0o600 }); chmodSync(temp, 0o600);
  const descriptor = openSync(temp, "r"); try { fsyncSync(descriptor); } finally { closeSync(descriptor); }
  renameSync(temp, target);
  const parent = openSync(directory, "r"); try { fsyncSync(parent); } finally { closeSync(parent); }
  return payload;
}

export function removeLaunchStatus(dataDir: string, id: string): boolean {
  try {
    const directory = containedPath(join(dataDir, "launches"), safeIdentifier(id, "启动会话"));
    if (!existsSync(directory)) return true;
    if (existsSync(join(directory, "dll-journal.json"))) return false;
    const value = JSON.parse(readFileSync(join(directory, "status.json"), "utf8")) as GameLaunch;
    if (value.id !== id || !["exited", "stopped", "failed"].includes(value.status)) return false;
    rmSync(directory, { recursive: true }); return true;
  } catch { return false; }
}
