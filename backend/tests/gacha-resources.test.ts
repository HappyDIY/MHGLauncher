import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, expect, test, vi } from "vitest";
import { GachaResourceService } from "../src/services/gacha-resources";
import { MetadataRepository } from "../src/services/metadata-repository";
import type { MetadataSnapshot } from "../src/services/snap-metadata";

const roots: string[] = [];
const fixtureDir = join(process.cwd(), "src", "mhglauncher", "data");
afterEach(() => {
  vi.restoreAllMocks();
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("祈愿与角色共用 fixture 资料且不访问网络", async () => {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-gacha-resource-")); roots.push(dataDir);
  const fetcher = vi.spyOn(globalThis, "fetch");
  const repository = new MetadataRepository({
    dataDir, apiBaseUrl: "https://api.snaphutaorp.org", fixtureDir,
  });
  const service = new GachaResourceService(dataDir, repository, "https://api.snaphutaorp.org", false);
  expect(service.status()).toMatchObject({ state: "ready", version: "fixture" });
  expect((await service.events()).length).toBeGreaterThan(0);
  expect(service.enrich(record())).toMatchObject({ name: "阿蕾奇诺", rank: 5, icon_url: null });
  expect(service.enrichCharacter(character())).toMatchObject({ icon_url: null });
  expect(fetcher).not.toHaveBeenCalled();
});

test("fixture 强制刷新直接复用当前快照", async () => {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-gacha-resource-")); roots.push(dataDir);
  const repository = new MetadataRepository({
    dataDir, apiBaseUrl: "https://api.snaphutaorp.org", fixtureDir,
  });
  const service = new GachaResourceService(dataDir, repository, "https://api.snaphutaorp.org", false);
  await expect(service.install(true)).resolves.toMatchObject({ state: "ready", version: "fixture" });
});

test("新快照映射卡池、物品和角色全部分类素材", async () => {
  const dataDir = temporary();
  const repository = fakeRepository(snapshot());
  const service = new GachaResourceService(dataDir, repository, "https://api.snaphutaorp.org");
  expect(service.status()).toMatchObject({ state: "ready", event_count: 1, image_count: 5 });
  const events = await service.events();
  expect(events[0]).toMatchObject({
    orange_up: ["五星角色"], purple_up: [], banner_url: expect.stringContaining("/cache/"),
    orange_up_icons: { 五星角色: expect.stringContaining("/cache/") },
  });
  expect(service.currentEvents()).toEqual(events);
  expect(service.enrich({ ...record(), item_id: "", name: "测试武器" })).toMatchObject({
    item_id: "11501", item_type: "武器", rank: 5, icon_url: expect.stringContaining("/cache/"),
  });
  const sources = Object.values(JSON.parse(readFileSync(
    join(dataDir, "resources", "image-cache", "index.json"), "utf8",
  )) as Record<string, { url: string }>);
  expect(sources.map(({ url }) => url)).toEqual(expect.arrayContaining([
    "https://api.snaphutaorp.org/static/raw/AvatarIcon/Avatar_Test.png",
    "https://api.snaphutaorp.org/static/raw/EquipIcon/Weapon_Test.png",
  ]));
  const localized = service.enrichCharacter({
    ...character(), avatar_id: "10000001", payload: {
      id: 10000001, icon: "https://upload-bbs.mihoyo.com/old.png",
      weapon: { id: 11501 }, relics: [{ id: 1001 }], skills: [{ skill_id: 101 }],
      constellations: [{ id: 201 }],
    },
  });
  expect(localized.icon_url).toContain("/cache/");
  expect(localized.payload).toMatchObject({
    weapon: { icon: expect.stringContaining("/cache/") },
    relics: [{ icon: expect.stringContaining("/cache/") }],
    skills: [{ icon: expect.stringContaining("/cache/") }],
    constellations: [{ icon: expect.stringContaining("/cache/") }],
  });
});

test("无新快照时继续读取旧资源并支持文件路由", async () => {
  const dataDir = temporary(), root = join(dataDir, "resources", "gacha-history");
  const file = `images/${"a".repeat(64)}.img`;
  mkdirSync(join(root, "images"), { recursive: true });
  writeFileSync(join(root, file), Buffer.from("legacy"));
  writeFileSync(join(root, "catalog.json"), JSON.stringify(legacyCatalog(file)));
  const repository = fakeRepository();
  const service = new GachaResourceService(dataDir, repository, "https://api.snaphutaorp.org");
  expect(service.status()).toMatchObject({ state: "ready", version: "old", image_count: 1 });
  expect((await service.events())[0]?.banner_url).toContain("/v1/gacha-resources/files/");
  expect(service.enrich({ ...record(), item_id: "10000001" }))
    .toMatchObject({ name: "旧角色", rank: 5 });
  expect(service.enrichCharacter({ ...character(), avatar_id: "10000001" }).icon_url)
    .toContain("/v1/gacha-resources/files/");
  await expect(service.file(file)).resolves.toEqual(Buffer.from("legacy"));
  await expect(service.file("../secret")).resolves.toBeNull();
  await service.install();
  expect(repository.sync).toHaveBeenCalledWith(true);
});

test("没有任何资料时返回缺失状态和中文错误", async () => {
  const service = new GachaResourceService(
    temporary(), fakeRepository(), "https://api.snaphutaorp.org",
  );
  expect(service.status()).toMatchObject({ state: "missing", event_count: 0, image_count: 0 });
  expect(service.currentEvents()).toEqual([]);
  await expect(service.events()).rejects.toMatchObject({ code: "gacha_resource_missing" });
  expect(service.enrich(record()).icon_url).toBeNull();
});

function record() {
  return { id: "1", uid: "100000001", gacha_type: "301", uigf_gacha_type: "301",
    item_id: "10000096", name: "", item_type: "", rank: 0, time: "2026-01-01T00:00:00Z" };
}

function temporary(): string {
  const root = mkdtempSync(join(tmpdir(), "mhg-gacha-resource-")); roots.push(root); return root;
}
function fakeRepository(value?: MetadataSnapshot): MetadataRepository {
  return {
    status: () => ({ state: value ? "ready" : "missing", oid: value?.oid ?? null,
      last_checked_at: null, last_success_at: null, trigger_game_version: null,
      using_legacy_cache: !value, error: null }),
    snapshot: () => value, ensure: vi.fn(async () => value),
    sync: vi.fn(async () => ({ state: "ready" })),
  } as unknown as MetadataRepository;
}
function snapshot(): MetadataSnapshot {
  return {
    oid: "a".repeat(40), activatedAt: "2026-01-01T00:00:00Z",
    items: {
      "10000001": { name: "五星角色", kind: "角色", rank: 5, icon: "Avatar_Test", digest: "a" },
      "11501": { name: "测试武器", kind: "武器", rank: 5, icon: "Weapon_Test", digest: "b" },
    },
    events: [{ name: "测试卡池", version: "1.0", order: 1,
      banner: "https://upload-bbs.mihoyo.com/banner.png", from: "2026-01-01", to: "2026-01-20",
      type: 301, orange: [10000001], purple: [999] }],
    assets: {
      avatars: { "10000001": ["Avatar_Test", "a"] }, weapons: { "11501": ["Weapon_Test", "b"] },
      reliquaries: { "1001": ["Relic_Test", "c"] }, skills: { "101": ["Skill_Test", "d"] },
      talents: { "201": ["Talent_Test", "e"] },
    },
    achievements: [], goals: [],
  };
}
function legacyCatalog(file: string) {
  return {
    schema_version: 2, version: "old", metadata_revision: "old",
    events: [{ id: "event", version: "1.0", gacha_type: "301", name: "旧卡池",
      started_at: null, ended_at: null, orange_up: ["旧角色"], purple_up: [],
      banner_file: file, updated_at: "2025-01-01" }],
    items: { "10000001": ["旧角色", "角色", 5, file] },
    character_assets: {
      avatars: { "10000001": file }, weapons: {}, reliquaries: {}, skills: {}, talents: {},
    },
  };
}
function character() {
  return {
    uid: "100000001", avatar_id: "10000089", name: "芙宁娜", element: "Hydro", level: 90,
    rarity: 5, constellation: 1, fetter: 10, weapon_name: "静水流涌之辉", weapon_level: 90,
    icon_url: "https://remote/avatar.png", updated_at: "2026-01-01T00:00:00Z", payload: {},
  };
}
