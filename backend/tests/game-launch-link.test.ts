import {
  existsSync, mkdtempSync, mkdirSync, realpathSync, rmSync, symlinkSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test } from "vitest";
import { createGameLaunchLink, removeGameLaunchLink } from "../src/services/game-launch-link";

const roots: string[] = [];

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("创建并移除指向游戏目录的启动软链接", () => {
  const root = fixture(), game = join(root, "game"), session = join(root, "session");
  mkdirSync(game);
  const link = createGameLaunchLink(game, session);
  expect(realpathSync(link)).toBe(realpathSync(game));
  removeGameLaunchLink(link);
  expect(existsSync(link)).toBe(false);
  expect(() => removeGameLaunchLink(link)).not.toThrow();
});

test("拒绝覆盖已有启动路径", () => {
  const root = fixture(), game = join(root, "game"), session = join(root, "session");
  mkdirSync(game); mkdirSync(session);
  symlinkSync(game, join(session, "game"), "dir");
  expect(() => createGameLaunchLink(game, session)).toThrow("游戏启动软链接已存在");
});

test("清理时拒绝删除被替换的普通文件", () => {
  const root = fixture(), link = join(root, "game");
  writeFileSync(link, "replacement");
  expect(() => removeGameLaunchLink(link)).toThrow("游戏启动软链接已被替换");
});

function fixture(): string {
  const root = mkdtempSync(join(tmpdir(), "mhg-game-link-")); roots.push(root); return root;
}
