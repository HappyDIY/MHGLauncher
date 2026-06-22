import { createHash } from "node:crypto";
import {
  chmodSync, copyFileSync, existsSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync,
  renameSync, rmSync, writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { AppError } from "../core/errors";

export interface DllIntegrity { md5: string; sha256: string; size: number }
export const MHYPBASE_INTEGRITY: DllIntegrity = {
  md5: "dcb1b134e0e8bc3bb292eb41d17f5788",
  sha256: "941558c9761eadecfebe13f5aeef131e35abf11370e0eb798cbc2d1e356f04f1",
  size: 24_056_296,
};

export interface DllJournal {
  target: string; backup: string; original_exists: boolean; original_sha256: string; replacement_md5: string;
}

export function prepareDll(
  gameRoot: string, source: string, sessionDir: string, integrity = MHYPBASE_INTEGRITY,
): DllJournal | null {
  verifySource(source, integrity);
  const target = join(gameRoot, "mhypbase.dll");
  if (existsSync(target) && digest(target, "md5") === integrity.md5) return null;
  mkdirSync(sessionDir, { recursive: true, mode: 0o700 });
  const backup = join(sessionDir, "mhypbase.original.dll");
  const originalExists = existsSync(target);
  const originalSha256 = originalExists ? digest(target, "sha256") : "";
  if (originalExists) copyAtomic(target, backup, 0o600);
  copyAtomic(source, target, originalExists ? lstatSync(target).mode & 0o777 : 0o644);
  if (digest(target, "md5") !== integrity.md5) {
    if (originalExists) copyAtomic(backup, target, lstatSync(backup).mode & 0o777);
    else rmSync(target, { force: true });
    throw new AppError("mhypbase_replace_failed", "mhypbase.dll 原子替换校验失败", 500);
  }
  const journal = { target, backup, original_exists: originalExists, original_sha256: originalSha256, replacement_md5: integrity.md5 };
  writeAtomic(join(sessionDir, "dll-journal.json"), JSON.stringify(journal), 0o600);
  return journal;
}

export function restoreDll(journal: DllJournal | null): string {
  if (!journal) return "";
  if (!existsSync(journal.target) || digest(journal.target, "md5") !== journal.replacement_md5) {
    return "mhypbase.dll 已被其他程序修改，已保留外部版本";
  }
  if (!journal.original_exists) rmSync(journal.target, { force: true });
  else {
    if (!existsSync(journal.backup) || digest(journal.backup, "sha256") !== journal.original_sha256) {
      return "mhypbase.dll 原始备份校验失败，未执行恢复";
    }
    copyAtomic(journal.backup, journal.target, lstatSync(journal.backup).mode & 0o777);
  }
  return "";
}

export function verifySource(path: string, integrity = MHYPBASE_INTEGRITY): void {
  if (!existsSync(path) || !lstatSync(path).isFile()) throw new AppError("mhypbase_source_missing", "内置 mhypbase.dll 不存在", 500);
  if (lstatSync(path).size !== integrity.size || digest(path, "md5") !== integrity.md5 || digest(path, "sha256") !== integrity.sha256) {
    throw new AppError("mhypbase_source_invalid", "内置 mhypbase.dll 完整性校验失败", 500);
  }
}

function digest(path: string, algorithm: "md5" | "sha256"): string {
  return createHash(algorithm).update(readFileSync(path)).digest("hex");
}

function copyAtomic(source: string, target: string, mode: number): void {
  mkdirSync(dirname(target), { recursive: true });
  const temp = `${target}.${process.pid}.tmp`;
  copyFileSync(source, temp); chmodSync(temp, mode); fsyncSync(openSync(temp, "r")); renameSync(temp, target);
}

function writeAtomic(path: string, content: string, mode: number): void {
  const temp = `${path}.${process.pid}.tmp`;
  writeFileSync(temp, content, { mode }); fsyncSync(openSync(temp, "r")); renameSync(temp, path);
}
