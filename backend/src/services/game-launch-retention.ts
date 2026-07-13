import type { GameLaunch } from "../core/models";
import { removeLaunchStatus } from "./game-launch-status-store";
import { pruneTerminal } from "./task-retention";

interface Deletable { delete(key: string): boolean }

export function pruneLaunches(dataDir: string, launches: Map<string, GameLaunch>, associated: Deletable[]): void {
  const previous = new Map(launches);
  const removed = pruneTerminal(launches, ({ status }) => ["exited", "stopped", "failed"].includes(status), ({ updated_at }) => Date.parse(updated_at) || 0);
  for (const id of removed) {
    const value = previous.get(id);
    if (!removeLaunchStatus(dataDir, id) && value) { launches.set(id, value); continue; }
    for (const map of associated) map.delete(id);
  }
}
