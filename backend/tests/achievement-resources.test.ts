import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, describe, expect, test, vi } from "vitest";
import { AchievementResources } from "../src/services/achievement-resources";
import { MetadataRepository } from "../src/services/metadata-repository";

const roots: string[] = [];
const fixtureDir = join(process.cwd(), "src", "mhglauncher", "data");
afterEach(() => {
  vi.restoreAllMocks();
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("共享成就资料", () => {
  test("fixture 模式从内置快照读取且不访问网络", async () => {
    const dataDir = mkdtempSync(join(tmpdir(), "mhg-achievement-resource-")); roots.push(dataDir);
    const fetcher = vi.spyOn(globalThis, "fetch");
    const repository = new MetadataRepository({
      dataDir, apiBaseUrl: "https://api.snaphutaorp.org", fixtureDir,
    });
    const resources = new AchievementResources(dataDir, repository, "https://api.snaphutaorp.org", false);
    const loaded = await resources.metadata();
    expect(loaded.achievements.length).toBeGreaterThan(0);
    expect(loaded.goals.length).toBeGreaterThan(0);
    expect(resources.iconUrl("UI_AchievementIcon_Test")).toBeNull();
    expect(fetcher).not.toHaveBeenCalled();
  });

  test("拒绝越界插图名称", async () => {
    const dataDir = mkdtempSync(join(tmpdir(), "mhg-achievement-resource-")); roots.push(dataDir);
    const repository = new MetadataRepository({
      dataDir, apiBaseUrl: "https://api.snaphutaorp.org", fixtureDir,
    });
    const resources = new AchievementResources(dataDir, repository, "https://api.snaphutaorp.org", false);
    await expect(resources.icon("../secret")).rejects.toMatchObject({ code: "achievement_icon_invalid" });
  });

  test("无新快照时读取旧成就缓存", async () => {
    const dataDir = temporary(), root = join(dataDir, "resources", "achievements");
    mkdirSync(root, { recursive: true });
    writeFileSync(join(root, "Achievement.json"), JSON.stringify([{
      Id: 1, Goal: 2, Order: 3, Title: "旧成就", Description: "描述",
      Progress: 1, Version: "1.0",
    }]));
    writeFileSync(join(root, "AchievementGoal.json"), JSON.stringify([{
      Id: 2, Order: 1, Name: "旧分类", Icon: "UI_AchievementIcon_Test",
    }]));
    const resources = new AchievementResources(
      dataDir, emptyRepository(), "https://api.snaphutaorp.org",
    );
    await expect(resources.metadata()).resolves.toMatchObject({
      achievements: [{ Title: "旧成就" }], goals: [{ Name: "旧分类" }],
    });
    expect(resources.iconUrl("bad/name")).toBeNull();
  });

  test("缺失或损坏缓存返回不可用", async () => {
    const dataDir = temporary();
    const resources = new AchievementResources(
      dataDir, emptyRepository(), "https://api.snaphutaorp.org",
    );
    await expect(resources.metadata()).rejects.toMatchObject({
      code: "achievement_resources_unavailable",
    });
    const root = join(dataDir, "resources", "achievements");
    mkdirSync(root, { recursive: true });
    writeFileSync(join(root, "Achievement.json"), "{");
    writeFileSync(join(root, "AchievementGoal.json"), "[]");
    await expect(resources.metadata()).rejects.toMatchObject({
      code: "achievement_resources_unavailable",
    });
  });

  test("成就插图通过本地缓存下载并拒绝无效内容", async () => {
    const dataDir = temporary();
    const resources = new AchievementResources(
      dataDir, emptyRepository(), "https://api.snaphutaorp.org",
    );
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      new Response(Buffer.from("89504e470d0a1a0a", "hex"), { status: 200 }),
    );
    await expect(resources.icon("UI_AchievementIcon_Test"))
      .resolves.toEqual(Buffer.from("89504e470d0a1a0a", "hex"));

    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(new Response("invalid", { status: 200 }));
    await expect(resources.icon("UI_AchievementIcon_Other"))
      .rejects.toMatchObject({ code: "image_cache_invalid" });
  });
});

function temporary(): string {
  const root = mkdtempSync(join(tmpdir(), "mhg-achievement-resource-")); roots.push(root); return root;
}
function emptyRepository(): MetadataRepository {
  return {
    ensure: vi.fn(async () => undefined), snapshot: () => undefined,
  } as unknown as MetadataRepository;
}
