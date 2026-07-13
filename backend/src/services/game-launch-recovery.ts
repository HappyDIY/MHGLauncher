import { existsSync, lstatSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import type { DllJournal } from "./game-launch-files";
import { restoreDll } from "./game-launch-files";

export interface DllRecoveryResult { warnings: string[]; pending: boolean }

export function recoverInterruptedDlls(dataDir: string): DllRecoveryResult {
  const root = join(dataDir, "launches");
  if (!existsSync(root)) return { warnings: [], pending: false };
  const journals = readdirSync(root, { withFileTypes: true }).filter((entry) => entry.isDirectory())
    .map((entry) => join(root, entry.name, "dll-journal.json")).filter(existsSync);
  if (gameIsRunning()) return { warnings: [], pending: journals.length > 0 };
  const warnings: string[] = [];
  let pending = false;
  const parsed = journals.map((path) => readJournal(path)).sort((left, right) => right.generation.localeCompare(left.generation));
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
  const value = JSON.parse(readFileSync(path, "utf8")) as Partial<DllJournal> & { target: string; backup: string };
  if (value.schema === 2) return value as DllJournal;
  const mode = existsSync(value.backup) ? lstatSync(value.backup).mode & 0o777 : 0o644;
  return {
    schema: 2, generation: `legacy-${lstatSync(path).mtimeMs}`, phase: "installed", journal_path: path,
    target: value.target, backup: value.backup, original_exists: Boolean(value.original_exists),
    original_sha256: String(value.original_sha256 ?? ""), original_mode: mode,
    original_dev: "", original_ino: "", replacement_md5: String(value.replacement_md5 ?? ""),
  };
}
