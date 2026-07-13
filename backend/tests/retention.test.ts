import { existsSync, mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vitest";
import { pruneTerminal } from "../src/services/task-retention";
import { removeLaunchStatus } from "../src/services/game-launch-status-store";
import { RevisionNotifier } from "../src/services/revision-notifier";

test("终态对象按 TTL 和数量淘汰且不删除活动对象", () => {
  const values = new Map([["old", { terminal: true, time: 0 }], ["recent", { terminal: true, time: 100 }], ["active", { terminal: false, time: 0 }]]);
  expect(pruneTerminal(values, (value) => value.terminal, (value) => value.time, 3, 50, 100)).toEqual(["old"]);
  expect([...values.keys()]).toEqual(["recent", "active"]);
});

test("long-poll 到期后删除空 waiter 容器", async () => {
  const notifier = new RevisionNotifier<{ revision: number }>(), value = { revision: 0 };
  await notifier.wait("done", 0, 5, () => value);
  expect((notifier as unknown as { waiters: Map<string, unknown> }).waiters.size).toBe(0);
});

test("启动会话清理拒绝链接和带恢复 journal 的目录", () => {
  const data = mkdtempSync(join(tmpdir(), "launch-retention-")), launches = join(data, "launches"), external = mkdtempSync(join(tmpdir(), "launch-external-")); mkdirSync(launches);
  symlinkSync(external, join(launches, "linked")); expect(removeLaunchStatus(data, "linked")).toBe(false); expect(existsSync(external)).toBe(true);
  const pending = join(launches, "pending"); mkdirSync(pending); writeFileSync(join(pending, "status.json"), JSON.stringify({ id: "pending", status: "failed" })); writeFileSync(join(pending, "dll-journal.json"), "{}");
  expect(removeLaunchStatus(data, "pending")).toBe(false); expect(existsSync(pending)).toBe(true);
  rmSync(data, { recursive: true, force: true }); rmSync(external, { recursive: true, force: true });
});
