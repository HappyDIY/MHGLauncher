import { existsSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import type { DllJournal } from "./game-launch-files";
import { restoreDll } from "./game-launch-files";
import { detectGame } from "./game-detection";
import { AppError } from "../core/errors";

export interface DllRecoveryResult { warnings: string[]; pending: boolean }

export function recoverInterruptedDlls(dataDir: string): DllRecoveryResult {
  const root = join(dataDir, "launches");
  if (!existsSync(root)) return { warnings: [], pending: false };
  const journals = readdirSync(root, { withFileTypes: true }).filter((entry) => entry.isDirectory())
    .map((entry) => join(root, entry.name, "dll-journal.json")).filter(existsSync);
  if (gameIsRunning()) return { warnings: [], pending: journals.length > 0 };
  const warnings: string[] = [];
  let pending = false;
  const parsed: DllJournal[] = [];
  for (const path of journals) {
    try { parsed.push(readJournal(path)); }
    catch { pending = true; warnings.push("启动 DLL 恢复记录无效，已拒绝执行文件操作"); }
  }
  parsed.sort((left, right) => right.generation.localeCompare(left.generation));
  for (const journal of parsed) {
    try {
      const result = restoreDll(journal); pending ||= result.pending;
      if (result.warning) warnings.push(result.warning);
    } catch (error) {
      pending = true;
      warnings.push(error instanceof Error ? error.message : "启动 DLL 恢复失败");
    }
  }
  return { warnings, pending };
}

function gameIsRunning(): boolean {
  return spawnSync("/usr/bin/pgrep", ["-if", "YuanShen.exe"], { stdio: "ignore" }).status === 0;
}

function readJournal(path: string): DllJournal {
  const value = JSON.parse(readFileSync(path, "utf8")) as DllJournal;
  const session = dirname(path), gameRoot = dirname(value.target ?? ""), detected = detectGame(gameRoot);
  if (value.schema !== 2 || !["planned", "installed"].includes(value.phase)
    || resolve(value.journal_path ?? "") !== resolve(path)
    || resolve(value.backup ?? "") !== resolve(session, "mhypbase.original.dll")
    || basename(value.target ?? "").toLowerCase() !== "mhypbase.dll"
    || resolve(value.target ?? "") !== resolve(gameRoot, "mhypbase.dll")
    || !detected || resolve(detected.path) !== resolve(realpathSync(gameRoot))
    || !/^[a-f0-9]{32}$/i.test(value.replacement_md5)
    || value.original_exists && !/^[a-f0-9]{64}$/i.test(value.original_sha256)
    || !Number.isInteger(value.original_mode) || value.original_mode < 0 || value.original_mode > 0o777) {
    throw new AppError("dll_journal_invalid", "启动 DLL 恢复记录无效", 409);
  }
  return value;
}
