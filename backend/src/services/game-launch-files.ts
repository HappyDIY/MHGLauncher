import {
  chmodSync, closeSync, copyFileSync, existsSync, fsyncSync, lstatSync, mkdirSync, openSync,
  renameSync, rmSync, writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";
import { AppError } from "../core/errors";
import { hashFileSync } from "./file-hash";

export interface DllIntegrity { md5: string; sha256: string; size: number }
export const MHYPBASE_INTEGRITY: DllIntegrity = {
  md5: "dcb1b134e0e8bc3bb292eb41d17f5788",
  sha256: "941558c9761eadecfebe13f5aeef131e35abf11370e0eb798cbc2d1e356f04f1",
  size: 24_056_296,
};

export interface DllJournal {
  schema: 2; generation: string; phase: "planned" | "installed"; journal_path: string;
  target: string; backup: string; original_exists: boolean; original_sha256: string;
  original_mode: number; original_dev: string; original_ino: string; replacement_md5: string;
}
export interface DllRestoreResult { warning: string; pending: boolean }

const verifiedSources = new Map<string, string>();

export function prepareDll(
  gameRoot: string, source: string, sessionDir: string, integrity = MHYPBASE_INTEGRITY,
): DllJournal | null {
  verifySource(source, integrity);
  const target = join(gameRoot, "mhypbase.dll");
  if (existsSync(target) && !lstatSync(target).isFile()) throw new AppError("mhypbase_target_invalid", "mhypbase.dll 目标不是普通文件", 500);
  if (existsSync(target) && digest(target, "md5") === integrity.md5) return null;
  mkdirSync(sessionDir, { recursive: true, mode: 0o700 });
  const backup = join(sessionDir, "mhypbase.original.dll");
  const journalPath = join(sessionDir, "dll-journal.json");
  const originalExists = existsSync(target);
  const originalStat = originalExists ? lstatSync(target, { bigint: true }) : null;
  const originalSha256 = originalExists ? digest(target, "sha256") : "";
  const journal: DllJournal = {
    schema: 2, generation: `${Date.now()}-${randomUUID()}`, phase: "planned", journal_path: journalPath,
    target, backup, original_exists: originalExists, original_sha256: originalSha256,
    original_mode: originalStat ? Number(originalStat.mode & 0o777n) : 0o644,
    original_dev: originalStat?.dev.toString() ?? "", original_ino: originalStat?.ino.toString() ?? "",
    replacement_md5: integrity.md5,
  };
  writeAtomic(journalPath, JSON.stringify(journal), 0o600);
  if (originalExists) copyAtomic(target, backup, journal.original_mode);
  copyAtomic(source, target, journal.original_mode);
  if (digest(target, "md5") !== integrity.md5) {
    restoreDll(journal);
    throw new AppError("mhypbase_replace_failed", "mhypbase.dll 原子替换校验失败", 500);
  }
  journal.phase = "installed"; writeAtomic(journalPath, JSON.stringify(journal), 0o600);
  return journal;
}

export function restoreDll(journal: DllJournal | null): DllRestoreResult {
  if (!journal) return { warning: "", pending: false };
  if (journal.schema !== 2) return { warning: "mhypbase.dll 恢复记录版本无效", pending: true };
  if (journal.original_exists && existsSync(journal.target) && digest(journal.target, "sha256") === journal.original_sha256) {
    finishJournal(journal); return { warning: "", pending: false };
  }
  if (!journal.original_exists && !existsSync(journal.target)) {
    finishJournal(journal); return { warning: "", pending: false };
  }
  if (!existsSync(journal.target) || digest(journal.target, "md5") !== journal.replacement_md5) {
    return { warning: "mhypbase.dll 已被其他程序修改，恢复记录已保留", pending: true };
  }
  if (!journal.original_exists) rmSync(journal.target, { force: true });
  else {
    if (!existsSync(journal.backup) || digest(journal.backup, "sha256") !== journal.original_sha256) {
      return { warning: "mhypbase.dll 原始备份校验失败，恢复记录已保留", pending: true };
    }
    copyAtomic(journal.backup, journal.target, journal.original_mode);
  }
  if (journal.original_exists && digest(journal.target, "sha256") !== journal.original_sha256) {
    return { warning: "mhypbase.dll 恢复后校验失败，恢复记录已保留", pending: true };
  }
  finishJournal(journal); return { warning: "", pending: false };
}

function verifySource(path: string, integrity = MHYPBASE_INTEGRITY): void {
  if (!existsSync(path) || !lstatSync(path).isFile()) throw new AppError("mhypbase_source_missing", "内置 mhypbase.dll 不存在", 500);
  const stat = lstatSync(path, { bigint: true });
  const signature = `${stat.dev}:${stat.ino}:${stat.size}:${stat.mtimeNs}:${stat.ctimeNs}`;
  if (stat.size !== BigInt(integrity.size)) throw new AppError("mhypbase_source_invalid", "内置 mhypbase.dll 完整性校验失败", 500);
  if (verifiedSources.get(path) === signature) return;
  const md5 = hashFileSync(path, "md5"), sha256 = hashFileSync(path, "sha256");
  if (md5 !== integrity.md5 || sha256 !== integrity.sha256) {
    throw new AppError("mhypbase_source_invalid", "内置 mhypbase.dll 完整性校验失败", 500);
  }
  verifiedSources.set(path, signature);
}

function digest(path: string, algorithm: "md5" | "sha256"): string {
  return hashFileSync(path, algorithm);
}

function copyAtomic(source: string, target: string, mode: number): void {
  mkdirSync(dirname(target), { recursive: true });
  const temp = `${target}.${randomUUID()}.tmp`;
  copyFileSync(source, temp); chmodSync(temp, mode); syncFile(temp); renameSync(temp, target); syncDirectory(dirname(target));
}

function writeAtomic(path: string, content: string, mode: number): void {
  const temp = `${path}.${randomUUID()}.tmp`;
  writeFileSync(temp, content, { mode, flag: "wx" }); syncFile(temp); renameSync(temp, path); syncDirectory(dirname(path));
}

function syncFile(path: string): void { const fd = openSync(path, "r"); try { fsyncSync(fd); } finally { closeSync(fd); } }
function syncDirectory(path: string): void { const fd = openSync(path, "r"); try { fsyncSync(fd); } finally { closeSync(fd); } }
function finishJournal(journal: DllJournal): void {
  rmSync(journal.backup, { force: true }); rmSync(journal.journal_path, { force: true });
  syncDirectory(dirname(journal.journal_path)); syncDirectory(dirname(journal.target));
}
