import { existsSync, readFileSync, readdirSync, renameSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import type { DllJournal } from "./game-launch-files";
import { restoreDll } from "./game-launch-files";

export function recoverInterruptedDlls(dataDir: string): string[] {
  const root = join(dataDir, "launches");
  if (!existsSync(root) || gameIsRunning()) return [];
  const warnings: string[] = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const journalPath = join(root, entry.name, "dll-journal.json");
    if (!existsSync(journalPath)) continue;
    try {
      const journal = JSON.parse(readFileSync(journalPath, "utf8")) as DllJournal;
      const warning = restoreDll(journal);
      if (warning) warnings.push(warning);
      renameSync(journalPath, `${journalPath}.restored`);
    } catch (error) {
      warnings.push(error instanceof Error ? error.message : "启动 DLL 恢复失败");
    }
  }
  return warnings;
}

function gameIsRunning(): boolean {
  return spawnSync("/usr/bin/pgrep", ["-if", "YuanShen.exe"], { stdio: "ignore" }).status === 0;
}
