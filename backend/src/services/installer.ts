import { constants, cpSync, closeSync, existsSync, fsyncSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, renameSync, rmSync, writeSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { AppError } from "../core/errors";
import { hash } from "./download";
import { containedPath } from "../core/safe-path";
import { ensureOwnedDirectory } from "../core/safe-path";

export function safeTarget(root: string, name: string): string {
  return containedPath(root, name);
}

export function extract(archives: string[], staging: string): void {
  mkdirSync(staging, { recursive: true });
  for (const archive of archives) {
    const listed = spawnSync("/usr/bin/unzip", ["-Z1", archive], { encoding: "utf8" });
    if (listed.status !== 0) throw new AppError("archive_unsupported", `${archive} 不是受支持的 ZIP 包`);
    for (const name of listed.stdout.split("\n").filter(Boolean)) safeTarget(staging, name);
    const modes = spawnSync("/usr/bin/unzip", ["-Z", "-l", archive], { encoding: "utf8" });
    if (modes.status !== 0 || modes.stdout.split("\n").some(unsupportedArchiveEntry)) {
      throw new AppError("archive_link_unsupported", "压缩包包含链接或特殊文件");
    }
    const result = spawnSync("/usr/bin/unzip", ["-qq", "-o", archive, "-d", staging], { encoding: "utf8" });
    if (result.status !== 0) throw new AppError("archive_extract_failed", `压缩包解压失败：${result.stderr}`);
  }
}

export function verify(staging: string): void {
  const path = resolve(staging, "mhg-manifest.json"); if (!existsSync(path)) return;
  const manifest = JSON.parse(readFileSync(path, "utf8")) as { files?: Record<string, string> };
  for (const [name, expected] of Object.entries(manifest.files ?? {})) {
    const target = safeTarget(staging, name);
    if (!existsSync(target) || hash(target, "sha256") !== expected) throw new AppError("installed_file_invalid", `${name} 安装校验失败`);
  }
}

interface DirectoryIdentity { dev: string; ino: string }
interface ActivationJournal {
  schema: 2; staging_name: string; backup_name: string; phase: "backing_up" | "promoting";
  staging: DirectoryIdentity; destination: DirectoryIdentity | null;
}
const stagingMarkers = new Set([".mhg-owner.json", ".mhg-staging.json", ".mhg-staging-version"]);

export function activate(
  staging: string, destination: string, fault?: (phase: string) => void, replaceExisting = true,
): void {
  const parent = dirname(destination), journalPath = `${destination}.mhg-activation.json`;
  if (dirname(staging) !== parent) throw new AppError("activation_cross_volume", "暂存目录必须与游戏目录位于同一父目录");
  recoverActivation(destination);
  const stagingIdentity = directoryIdentity(staging, "游戏暂存目录");
  const destinationIdentity = existsSync(destination) ? directoryIdentity(destination, "游戏安装目录") : null;
  if (!replaceExisting && destinationIdentity && readdirSync(destination).length > 0) {
    throw new AppError("install_destination_not_empty", "所选安装目录不为空，已拒绝覆盖其中的文件", 409);
  }
  const backup = join(parent, `${basename(destination)}.mhg-backup-${randomUUID()}`);
  const journal: ActivationJournal = {
    schema: 2, staging_name: basename(staging), backup_name: basename(backup), phase: "backing_up",
    staging: stagingIdentity, destination: destinationIdentity,
  };
  writeJournal(journalPath, journal); fault?.("before_backup");
  let backedUp = false, promoted = false;
  try {
    if (destinationIdentity) {
      renameSync(destination, backup); backedUp = true;
      if (!sameDirectory(backup, destinationIdentity) || !replaceExisting && readdirSync(backup).length > 0) {
        throw new AppError("install_destination_changed", "安装期间目标目录发生变化，已停止提交", 409);
      }
    }
    fault?.("after_backup"); journal.phase = "promoting"; writeJournal(journalPath, journal);
    renameSync(staging, destination); promoted = true; fault?.("after_promote");
  } catch (error) {
    if (promoted && sameDirectory(destination, stagingIdentity)) rmSync(destination, { recursive: true });
    if (backedUp && sameDirectory(backup, destinationIdentity) && !existsSync(destination)) renameSync(backup, destination);
    if (!existsSync(backup) && (!destinationIdentity || sameDirectory(destination, destinationIdentity))) rmSync(journalPath, { force: true });
    throw error;
  }
  fault?.("before_cleanup");
  if (destinationIdentity) {
    if (!sameDirectory(backup, destinationIdentity)) throw new AppError("activation_backup_changed", "游戏备份目录身份异常，已停止清理", 409);
    rmSync(backup, { recursive: true });
  }
  rmSync(journalPath, { force: true });
}

export function recoverActivation(destination: string): void {
  const journalPath = `${destination}.mhg-activation.json`;
  if (!existsSync(journalPath)) return;
  const parent = dirname(destination), base = basename(destination);
  let value: ActivationJournal;
  try { value = JSON.parse(readFileSync(journalPath, "utf8")) as ActivationJournal; }
  catch { throw new AppError("activation_journal_invalid", "游戏激活恢复记录损坏"); }
  if (value.schema !== 2 || !["backing_up", "promoting"].includes(value.phase) || !validIdentity(value.staging)
    || value.destination !== null && !validIdentity(value.destination)
    || basename(value.backup_name) !== value.backup_name || basename(value.staging_name) !== value.staging_name
    || !value.backup_name.startsWith(`${base}.mhg-backup-`) || !value.staging_name.startsWith(`${base}.mhg-staging-`)) {
    throw new AppError("activation_journal_invalid", "游戏激活恢复记录无效");
  }
  const backup = join(parent, value.backup_name), staging = join(parent, value.staging_name);
  const destinationIsStaging = sameDirectory(destination, value.staging);
  const destinationIsOriginal = sameDirectory(destination, value.destination);
  const stagingMatches = sameDirectory(staging, value.staging);
  const backupMatches = sameDirectory(backup, value.destination);
  if (existsSync(destination) && !destinationIsStaging && !destinationIsOriginal) invalidActivationState();
  if (existsSync(staging) && !stagingMatches) invalidActivationState();
  if (existsSync(backup) && !backupMatches) invalidActivationState();
  if (value.phase === "promoting" && destinationIsStaging && !existsSync(staging)) {
    if (backupMatches) rmSync(backup, { recursive: true });
  } else if (backupMatches && !existsSync(destination)) {
    renameSync(backup, destination);
    if (stagingMatches) rmSync(staging, { recursive: true });
  } else if (value.destination && destinationIsOriginal) {
    if (stagingMatches) rmSync(staging, { recursive: true });
  } else if (!value.destination && !existsSync(destination) && stagingMatches) {
    renameSync(staging, destination);
  } else if (!destinationIsStaging) {
    invalidActivationState();
  }
  rmSync(journalPath, { force: true });
}

function directoryIdentity(path: string, label: string): DirectoryIdentity {
  const stat = lstatSync(path, { bigint: true });
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new AppError("activation_path_invalid", `${label}不是普通目录`, 409);
  return { dev: stat.dev.toString(), ino: stat.ino.toString() };
}

function sameDirectory(path: string, expected: DirectoryIdentity | null): boolean {
  if (!expected || !existsSync(path)) return false;
  try { const actual = directoryIdentity(path, "激活目录"); return actual.dev === expected.dev && actual.ino === expected.ino; }
  catch { return false; }
}

function validIdentity(value: DirectoryIdentity | null | undefined): value is DirectoryIdentity {
  return Boolean(value && /^\d+$/.test(value.dev) && /^\d+$/.test(value.ino));
}

function invalidActivationState(): never {
  throw new AppError("activation_state_conflict", "游戏目录身份与恢复记录不一致，已拒绝自动删除", 409);
}

export function stageExisting(source: string, staging: string, owner: string, initialize: () => void): void {
  if (existsSync(staging)) throw new AppError("staging_exists", "游戏暂存目录已存在");
  ensureOwnedDirectory(staging, owner); initialize();
  if (existsSync(source)) cpSync(source, staging, {
    recursive: true, mode: constants.COPYFILE_FICLONE,
    filter: (entry) => !stagingMarkers.has(basename(entry)),
  });
}

export function ensureParent(path: string): void { mkdirSync(dirname(path), { recursive: true }); }

function writeJournal(path: string, value: ActivationJournal): void {
  const temp = `${path}.${randomUUID()}.tmp`, descriptor = openSync(temp, "wx", 0o600);
  try { writeSync(descriptor, JSON.stringify(value)); fsyncSync(descriptor); } finally { closeSync(descriptor); }
  renameSync(temp, path);
  const directory = openSync(dirname(path), "r"); try { fsyncSync(directory); } finally { closeSync(directory); }
}

function unsupportedArchiveEntry(line: string): boolean {
  const match = /^([bcdlps-])[rwxStTs-]{9}\s/.exec(line);
  return match !== null && match[1] !== "-" && match[1] !== "d";
}
