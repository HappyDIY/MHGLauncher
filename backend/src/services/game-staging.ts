import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync, rmSync, type Dirent } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import type { JobKind } from "../core/models";
import { ensureOwnedDirectory, removeOwnedDirectory, safeIdentifier } from "../core/safe-path";
import { managedPath, writeManagedFile } from "./managed-file";
import { stageExisting } from "./installer";

const METADATA = ".mhg-staging.json";
const VERSION = ".mhg-staging-version";

export interface GameStagingRecord {
  schema: 1; owner: string; pid: number; kind: JobKind;
  destination: string; version: string;
}

export function createGameStaging(
  path: string, owner: string, kind: JobKind, destination: string, version: string,
): GameStagingRecord {
  const record: GameStagingRecord = {
    schema: 1, owner: safeIdentifier(owner, "暂存任务"), pid: process.pid, kind,
    destination: resolve(destination), version: safeIdentifier(version, "暂存版本"),
  };
  ensureOwnedDirectory(path, record.owner);
  writeManagedFile(path, METADATA, JSON.stringify(record));
  writeManagedFile(path, VERSION, record.version);
  return record;
}

export function stageGameExisting(
  source: string, path: string, owner: string, kind: JobKind, destination: string, version: string,
): GameStagingRecord {
  let record: GameStagingRecord | null = null;
  try { stageExisting(source, path, owner, () => { record = createGameStaging(path, owner, kind, destination, version); }); }
  catch (error) {
    if (!record || kind !== "install") try { removeOwnedDirectory(path, owner); } catch { /* 无法确认所有权时保留目录。 */ }
    throw error;
  }
  if (!record) throw new Error("暂存目录所有权记录未创建");
  return record;
}

export function readGameStaging(path: string, destination?: string): GameStagingRecord | null {
  try {
    if (!existsSync(path)) return null;
    const stat = lstatSync(path); if (!stat.isDirectory() || stat.isSymbolicLink()) return null;
    const value = JSON.parse(readFileSync(managedPath(path, METADATA), "utf8")) as GameStagingRecord;
    if (value.schema !== 1 || !Number.isSafeInteger(value.pid) || value.pid <= 0
      || !["install", "update"].includes(value.kind) || resolve(value.destination) !== value.destination
      || destination && canonicalPath(destination) !== canonicalPath(value.destination)) return null;
    safeIdentifier(value.owner, "暂存任务"); safeIdentifier(value.version, "暂存版本");
    ensureOwnedDirectory(path, value.owner);
    if (readFileSync(managedPath(path, VERSION), "utf8").trim() !== value.version) return null;
    return value;
  } catch { return null; }
}

export function clearGameStagingMarkers(path: string): void {
  for (const name of [METADATA, VERSION, ".mhg-owner.json"]) rmSync(managedPath(path, name), { force: true });
}

function removeGameStaging(path: string, record: GameStagingRecord): void {
  const current = readGameStaging(path, record.destination);
  if (!current || current.owner !== record.owner || current.kind !== record.kind) return;
  removeOwnedDirectory(path, record.owner);
}

export function finishGameStaging(path: string, record: GameStagingRecord | null, preserve: boolean): void {
  if (record && !preserve) removeGameStaging(path, record);
}

export function cleanupStaleUpdateStaging(destination: string): void {
  const target = canonicalPath(destination), parent = dirname(target), prefix = `${basename(target)}.mhg-staging-`;
  let entries: Dirent[];
  try { entries = readdirSync(parent, { withFileTypes: true }); } catch { return; }
  for (const entry of entries) {
    if (!entry.isDirectory() || !entry.name.startsWith(prefix)) continue;
    const path = join(parent, entry.name), record = readGameStaging(path, target);
    if (record?.kind === "update" && !processAlive(record.pid)) {
      try { removeGameStaging(path, record); } catch { /* 清理失败不影响当前资源任务。 */ }
    }
  }
}

function processAlive(pid: number): boolean {
  try { process.kill(pid, 0); return true; }
  catch (error) { return (error as NodeJS.ErrnoException).code !== "ESRCH"; }
}

function canonicalPath(path: string): string {
  let current = resolve(path); const suffix: string[] = [];
  while (!existsSync(current)) {
    const parent = dirname(current); if (parent === current) return current;
    suffix.unshift(basename(current)); current = parent;
  }
  return resolve(realpathSync(current), ...suffix);
}
