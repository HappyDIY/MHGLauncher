import { mkdtempSync, mkdirSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, test } from "vitest";
import { ResourceCoordinator } from "../src/services/resource-coordinator";

test("尚未创建的游戏目录通过符号链接别名共享资源锁", () => {
  const root = mkdtempSync(join(tmpdir(), "resource-alias-")), physical = join(root, "physical");
  const firstAlias = join(root, "first"), secondAlias = join(root, "second");
  mkdirSync(physical); symlinkSync(physical, firstAlias); symlinkSync(physical, secondAlias);
  const coordinator = new ResourceCoordinator(), first = join(firstAlias, "Genshin Impact Game");
  coordinator.claim(first, "first-job");
  expect(() => coordinator.claim(join(secondAlias, "Genshin Impact Game"), "second-job")).toThrow("正在被其他任务使用");
  expect(coordinator.busy(join(physical, "Genshin Impact Game"))).toBe(true);
});
