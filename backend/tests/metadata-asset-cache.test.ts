import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test, vi } from "vitest";
import { ImageResourceCache } from "../src/services/image-resource-cache";
import { MetadataAssetCache } from "../src/services/metadata-asset-cache";
import type { MetadataRepository } from "../src/services/metadata-repository";
import type { MetadataSnapshot } from "../src/services/snap-metadata";

const roots: string[] = [];
afterEach(() => {
  vi.restoreAllMocks();
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("启动预取全部资料插图并复用本地缓存", async () => {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-metadata-assets-")); roots.push(dataDir);
  const fetcher = vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
    new Response(Buffer.from("89504e470d0a1a0a", "hex")));
  const images = new ImageResourceCache(dataDir);
  const cache = new MetadataAssetCache(dataDir, repository(snapshot()), images);
  expect(cache.status()).toMatchObject({
    asset_state: "missing", initial_install_required: true,
  });
  await cache.preload();

  const root = join(dataDir, "resources", "image-cache");
  const index = JSON.parse(readFileSync(join(root, "index.json"), "utf8")) as
    Record<string, { url: string }>;
  const urls = Object.values(index).map(({ url }) => url);
  expect(urls).toHaveLength(8);
  expect(urls).toEqual(expect.arrayContaining([
    "https://api.snaphutaorp.org/static/raw/AvatarIcon/Avatar.png",
    "https://api.snaphutaorp.org/static/raw/EquipIcon/Weapon.png",
    "https://api.snaphutaorp.org/static/raw/RelicIcon/Relic.png",
    "https://api.snaphutaorp.org/static/raw/Skill/Skill.png",
    "https://api.snaphutaorp.org/static/raw/Talent/Talent.png",
    "https://api.snaphutaorp.org/static/raw/AchievementIcon/Achievement.png",
    "https://api.snaphutaorp.org/static/raw/AchievementIcon/Goal.png",
    "https://upload-bbs.mihoyo.com/banner.png",
  ]));
  expect(Object.keys(index).every((name) => existsSync(join(root, name)))).toBe(true);
  expect(fetcher).toHaveBeenCalledTimes(8);
  expect(cache.status()).toMatchObject({
    asset_state: "ready", asset_completed: 8, asset_total: 8,
    asset_failed: 0, initial_install_required: false,
  });

  await cache.preload();
  expect(fetcher).toHaveBeenCalledTimes(8);
  expect(new MetadataAssetCache(dataDir, repository(snapshot()), images).status())
    .toMatchObject({ asset_state: "ready", initial_install_required: false });
});

function repository(value: MetadataSnapshot): MetadataRepository {
  return { snapshot: () => value } as unknown as MetadataRepository;
}

function snapshot(): MetadataSnapshot {
  return {
    oid: "a".repeat(40), activatedAt: "2026-01-01T00:00:00Z", items: {}, events: [{
      name: "测试卡池", version: "1.0", order: 1, banner: "https://upload-bbs.mihoyo.com/banner.png",
      from: "2026-01-01", to: "2026-01-20", type: 301, orange: [], purple: [],
    }],
    assets: {
      avatars: { "1": ["Avatar", "avatar"] },
      weapons: { "2": ["Weapon", "weapon"] },
      reliquaries: { "3": ["Relic", "relic"] },
      skills: { "4": ["Skill", "skill"] },
      talents: { "5": ["Talent", "talent"] },
    },
    achievements: [{ Id: 1, Goal: 1, Order: 1, Title: "成就", Description: "描述",
      Progress: 1, Version: "1.0", Icon: "Achievement" }],
    goals: [{ Id: 1, Order: 1, Name: "目标", Icon: "Goal" }],
  };
}
