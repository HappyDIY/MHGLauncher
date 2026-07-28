import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import xxhash from "xxhash-wasm";
import { afterEach, expect, test, vi } from "vitest";
import { discoverMirrors } from "../src/services/metadata-remote";
import { MetadataRepository } from "../src/services/metadata-repository";
import { validateMetadataRepository } from "../src/services/metadata-validation";

const roots: string[] = [];
afterEach(() => {
  vi.restoreAllMocks();
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("镜像发现保留返回顺序并拒绝 HTTP 镜像", async () => {
  const result = await discoverMirrors("https://api.snaphutaorp.org", async () => Response.json({
    code: 0, data: [
      { https_url: "https://first.example/Snap.Metadata.git" },
      { https_url: "http://unsafe.example/Snap.Metadata.git" },
      { https_url: "https://second.example/Snap.Metadata.git" },
    ],
  }));
  expect(result).toEqual([
    "https://first.example/Snap.Metadata.git", "https://second.example/Snap.Metadata.git",
  ]);
});

test("同步按镜像故障转移、合并并发并按 OID 跳过", async () => {
  const dataDir = temporary(), clones: string[] = [];
  const clone = vi.fn(async (url: string, dir: string) => {
    clones.push(url);
    if (url.includes("first")) throw new Error("first failed");
    await writeRepository(dir);
  });
  const repository = new MetadataRepository({
    dataDir, apiBaseUrl: "https://api.example",
    discover: async () => ["https://first.example/repo.git", "https://second.example/repo.git"],
    oid: async () => "b".repeat(40), clone,
  });
  const [left, right] = await Promise.all([repository.sync(), repository.sync()]);
  expect(left).toMatchObject({ state: "ready", oid: "b".repeat(40) });
  expect(right).toEqual(left);
  expect(clones).toEqual(["https://first.example/repo.git", "https://second.example/repo.git"]);
  await repository.sync();
  expect(clone).toHaveBeenCalledTimes(2);
  expect(existsSync(join(dataDir, "resources", "Snap.Metadata", "Genshin", "CHS", "Meta.json"))).toBe(true);
});

test("损坏新快照保留旧快照并进入待重试状态", async () => {
  const dataDir = temporary();
  let oid = "a".repeat(40), corrupt = false;
  const repository = new MetadataRepository({
    dataDir, apiBaseUrl: "https://api.example",
    discover: async () => ["https://mirror.example/repo.git"],
    oid: async () => oid,
    clone: async (_url, dir) => {
      await writeRepository(dir);
      if (corrupt) writeFileSync(join(dir, "Genshin", "CHS", "Weapon.json"), "[]");
    },
  });
  await repository.sync();
  corrupt = true; oid = "b".repeat(40);
  await expect(repository.sync()).resolves.toMatchObject({
    state: "retry", oid: "a".repeat(40),
  });
  expect(repository.snapshot()?.oid).toBe("a".repeat(40));
});

test("xxHash64 不匹配时拒绝资料", async () => {
  const root = temporary();
  await writeRepository(root);
  writeFileSync(join(root, "Genshin", "CHS", "Weapon.json"), "[]");
  await expect(validateMetadataRepository(root)).rejects.toMatchObject({ code: "metadata_invalid" });
});

test("拒绝摘要路径穿越和仓库符号链接", async () => {
  const traversal = temporary();
  await writeRepository(traversal);
  const metaPath = join(traversal, "Genshin", "CHS", "Meta.json");
  const meta = JSON.parse(readFileSync(metaPath, "utf8")) as Record<string, string>;
  meta["../outside"] = "0".repeat(16); writeFileSync(metaPath, JSON.stringify(meta));
  await expect(validateMetadataRepository(traversal)).rejects.toMatchObject({ code: "metadata_invalid" });

  const linked = temporary();
  await writeRepository(linked);
  symlinkSync("/tmp", join(linked, "unsafe-link"));
  await expect(validateMetadataRepository(linked)).rejects.toMatchObject({ code: "metadata_invalid" });
});

async function writeRepository(root: string): Promise<void> {
  const chs = join(root, "Genshin", "CHS"), avatar = join(chs, "Avatar");
  mkdirSync(avatar, { recursive: true });
  const files: Record<string, unknown> = {
    GachaEvent: [{ Name: "测试卡池", Version: "1.0", Order: 1,
      Banner: "https://upload-bbs.mihoyo.com/test.png", From: "2026-01-01T00:00:00+08:00",
      To: "2026-01-20T00:00:00+08:00", Type: 301, UpOrangeList: [10000001], UpPurpleList: [] }],
    Weapon: [{ Id: 11501, Name: "测试武器", Icon: "UI_EquipIcon_Test", RankLevel: 5 }],
    Reliquary: [{ Ids: [1001], Icon: "UI_RelicIcon_Test" }],
    Achievement: [{ Id: 1, Goal: 1, Order: 1, Title: "测试", Description: "测试",
      Progress: 1, Version: "1.0", Icon: "UI_AchievementIcon_Test" }],
    AchievementGoal: [{ Id: 1, Order: 1, Name: "测试", Icon: "UI_AchievementIcon_Test" }],
    "Avatar/10000001": { Id: 10000001, Name: "测试角色", Icon: "UI_AvatarIcon_Test",
      RankLevel: 5, Quality: 105, SkillDepot: {
        Skills: [{ Id: 101, Icon: "Skill_Test" }], Talents: [{ Id: 201, Icon: "Talent_Test" }],
      } },
    "Avatar/10000002": { Id: 10000002, Name: "测试四星角色", Icon: "UI_AvatarIcon_Test4",
      RankLevel: 4, Quality: 4, SkillDepot: { Skills: [], Talents: [] } },
  };
  const { h64Raw } = await xxhash(), meta: Record<string, string> = {};
  for (const [key, value] of Object.entries(files)) {
    const path = join(chs, `${key}.json`), data = Buffer.from(JSON.stringify(value));
    mkdirSync(join(path, ".."), { recursive: true }); writeFileSync(path, data);
    meta[key] = h64Raw(data).toString(16).padStart(16, "0").toUpperCase();
  }
  writeFileSync(join(chs, "Meta.json"), JSON.stringify(meta));
}
function temporary(): string {
  const root = mkdtempSync(join(tmpdir(), "mhg-metadata-")); roots.push(root); return root;
}
