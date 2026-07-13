import { cpSync, closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, rmSync, writeSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { AppError } from "../core/errors";
import { hash } from "./download";
import { containedPath } from "../core/safe-path";

export function safeTarget(root: string, name: string): string {
  return containedPath(root, name);
}

export function extract(archives: string[], staging: string): void {
  mkdirSync(staging, { recursive: true });
  for (const archive of archives) {
    const listed = spawnSync("/usr/bin/unzip", ["-Z1", archive], { encoding: "utf8" });
    if (listed.status !== 0) throw new AppError("archive_unsupported", `${archive} 不是受支持的 ZIP 包`);
    for (const name of listed.stdout.split("\n").filter(Boolean)) safeTarget(staging, name);
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

interface ActivationJournal { schema: 1; staging_name: string; backup_name: string; phase: "backing_up" | "promoting" }

export function activate(staging: string, destination: string, fault?: (phase: string) => void): void {
  const parent = dirname(destination), journalPath = `${destination}.mhg-activation.json`;
  if (dirname(staging) !== parent) throw new AppError("activation_cross_volume", "暂存目录必须与游戏目录位于同一父目录");
  recoverActivation(destination);
  const hadDestination = existsSync(destination);
  const backup = join(parent, `${basename(destination)}.mhg-backup-${randomUUID()}`);
  const journal: ActivationJournal = { schema: 1, staging_name: basename(staging), backup_name: basename(backup), phase: "backing_up" };
  writeJournal(journalPath, journal); fault?.("before_backup");
  try {
    if (hadDestination) renameSync(destination, backup);
    fault?.("after_backup"); journal.phase = "promoting"; writeJournal(journalPath, journal);
    renameSync(staging, destination); fault?.("after_promote");
    rmSync(backup, { recursive: true, force: true }); rmSync(journalPath, { force: true });
  } catch (error) {
    if (existsSync(destination) && (existsSync(backup) || !hadDestination)) rmSync(destination, { recursive: true, force: true });
    if (existsSync(backup) && !existsSync(destination)) renameSync(backup, destination);
    rmSync(journalPath, { force: true }); throw error;
  }
}

export function recoverActivation(destination: string): void {
  const journalPath = `${destination}.mhg-activation.json`;
  if (!existsSync(journalPath)) return;
  const parent = dirname(destination), base = basename(destination);
  let value: ActivationJournal;
  try { value = JSON.parse(readFileSync(journalPath, "utf8")) as ActivationJournal; }
  catch { throw new AppError("activation_journal_invalid", "游戏激活恢复记录损坏"); }
  if (value.schema !== 1 || basename(value.backup_name) !== value.backup_name || basename(value.staging_name) !== value.staging_name
    || !value.backup_name.startsWith(`${base}.mhg-backup-`) || !value.staging_name.startsWith(`${base}.mhg-staging-`)) {
    throw new AppError("activation_journal_invalid", "游戏激活恢复记录无效");
  }
  const backup = join(parent, value.backup_name), staging = join(parent, value.staging_name);
  const promoted = value.phase === "promoting" && existsSync(destination) && !existsSync(staging);
  if (promoted) rmSync(backup, { recursive: true, force: true });
  else if (existsSync(backup)) {
    rmSync(destination, { recursive: true, force: true }); renameSync(backup, destination);
  }
  rmSync(staging, { recursive: true, force: true }); rmSync(journalPath, { force: true });
}

export function stageExisting(source: string, staging: string): void {
  if (existsSync(staging)) throw new AppError("staging_exists", "游戏暂存目录已存在");
  if (existsSync(source)) cpSync(source, staging, { recursive: true }); else mkdirSync(staging, { recursive: true });
}

export function ensureParent(path: string): void { mkdirSync(dirname(path), { recursive: true }); }

function writeJournal(path: string, value: ActivationJournal): void {
  const temp = `${path}.${randomUUID()}.tmp`, descriptor = openSync(temp, "wx", 0o600);
  try { writeSync(descriptor, JSON.stringify(value)); fsyncSync(descriptor); } finally { closeSync(descriptor); }
  renameSync(temp, path);
  const directory = openSync(dirname(path), "r"); try { fsyncSync(directory); } finally { closeSync(directory); }
}
