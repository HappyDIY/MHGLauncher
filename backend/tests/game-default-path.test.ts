import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test } from "vitest";
import type { Store } from "../src/core/database";
import { FixtureProvider } from "../src/providers/fixture";
import { GameService } from "../src/services/games";

const roots: string[] = [];

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("未设置安装位置时使用应用私有目录", async () => {
  const root = mkdtempSync(join(tmpdir(), "mhg-default-game-"));
  const dataDir = join(root, "data"), fixtures = join(root, "fixtures");
  roots.push(root);
  mkdirSync(fixtures); writeFileSync(join(fixtures, "build.json"), JSON.stringify({ version: "6.7.0", assets: [] }));
  const store = { one: () => undefined } as unknown as Store;
  const service = new GameService(store, new FixtureProvider(fixtures), dataDir);
  const state = await service.state();
  expect(state.install_path).toBe(join(dataDir, "Games", "Genshin Impact Game"));
  expect(state.status).toBe("not_installed");
});
