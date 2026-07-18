import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, describe, expect, test } from "vitest";
import { AchievementResources } from "../src/services/achievement-resources";

const roots: string[] = [];
const metadataBaseUrl = "https://metadata.example/Genshin/CHS/";
const iconBaseUrl = "https://icons.example/AchievementIcon/";
const achievement = [{
  Id: 80001, Goal: 1, Order: 1, Title: "测试成就", Description: "测试描述",
  Progress: 1, Version: "1.0", Icon: "UI_AchievementIcon_Test",
}];
const goal = [{ Id: 1, Order: 1, Name: "测试目标", Icon: "UI_AchievementIcon_Test" }];
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1]);

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("成就独立资源", () => {
  test("下载条目与插图并从用户数据目录复用", async () => {
    const dataDir = mkdtempSync(join(tmpdir(), "mhg-achievement-resource-"));
    roots.push(dataDir);
    const calls: string[] = [];
    const fetcher = async (input: string): Promise<Response> => {
      calls.push(input);
      if (input.endsWith("Achievement.json")) return response(JSON.stringify(achievement), "metadata-a");
      if (input.endsWith("AchievementGoal.json")) return response(JSON.stringify(goal), "metadata-g");
      if (input.endsWith("UI_AchievementIcon_Test.png")) return new Response(Uint8Array.from(png));
      return new Response(null, { status: 404 });
    };
    const resources = new AchievementResources(dataDir, { metadataBaseUrl, iconBaseUrl, fetcher });

    const loaded = await resources.metadata();
    expect(loaded.achievements[0]?.Title).toBe("测试成就");
    expect(loaded.goals[0]?.Name).toBe("测试目标");
    expect(resources.iconUrl("UI_AchievementIcon_Test")).toBe(
      "/v1/achievements/resources/icons/UI_AchievementIcon_Test.png",
    );
    expect(await resources.icon("UI_AchievementIcon_Test")).toEqual(png);
    expect(calls).toHaveLength(3);

    const offline = new AchievementResources(dataDir, {
      metadataBaseUrl, iconBaseUrl,
      fetcher: async () => { throw new Error("offline"); },
    });
    expect((await offline.metadata()).achievements).toHaveLength(1);
    expect(await offline.icon("UI_AchievementIcon_Test")).toEqual(png);
  });

  test("拒绝越界插图名称", async () => {
    const dataDir = mkdtempSync(join(tmpdir(), "mhg-achievement-resource-"));
    roots.push(dataDir);
    const resources = new AchievementResources(dataDir, {
      metadataBaseUrl, iconBaseUrl,
      fetcher: async () => new Response(null, { status: 404 }),
    });
    await expect(resources.icon("../secret")).rejects.toMatchObject({ code: "achievement_icon_invalid" });
  });
});

function response(body: string, etag: string): Response {
  return new Response(body, { headers: { ETag: etag, "Content-Type": "application/json" } });
}
