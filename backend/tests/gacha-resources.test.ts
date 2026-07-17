import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { afterEach, expect, test, vi } from "vitest";
import { GachaResourceService } from "../src/services/gacha-resources";

const roots: string[] = [];
afterEach(() => { vi.restoreAllMocks(); for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

test("独立资源包下载、逐文件校验并提供本地插图", async () => {
  const fixture = packageFixture(), manifestUrl = "https://resource.example/gacha-history-manifest.json";
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    if (String(input) === manifestUrl) return Response.json(fixture.manifest);
    const data = readFileSync(fixture.archive);
    return new Response(data, { headers: { "Content-Length": String(data.length) } });
  });
  const service = new GachaResourceService(fixture.data, manifestUrl);
  expect(service.status().state).toBe("missing");
  expect(service.enrich(record()).icon_url).toBeNull();
  expect(service.enrichCharacter(character())).toMatchObject({
    icon_url: null, payload: { weapon: { icon: null }, relics: [{ icon: null }], skills: [{ icon: null }] },
  });
  await expect(service.install()).resolves.toMatchObject({ state: "ready", version: "fixture-1", event_count: 1, image_count: 1 });
  expect(service.events()[0]).toMatchObject({ banner_url: `/v1/gacha-resources/files/${fixture.file}?version=fixture-1` });
  expect(service.enrich(record())).toMatchObject({ name: "阿蕾奇诺", rank: 5, icon_url: `/v1/gacha-resources/files/${fixture.file}?version=fixture-1` });
  expect(service.enrichCharacter(character())).toMatchObject({
    icon_url: `/v1/gacha-resources/files/${fixture.file}?version=fixture-1`,
    payload: {
      weapon: { icon: `/v1/gacha-resources/files/${fixture.file}?version=fixture-1` },
      relics: [{ icon: `/v1/gacha-resources/files/${fixture.file}?version=fixture-1` }],
      skills: [{ icon: `/v1/gacha-resources/files/${fixture.file}?version=fixture-1` }],
    },
  });
  expect(service.file(fixture.file)?.toString()).toBe("fixture-image");
});

test("资源包摘要不匹配时保留未安装状态", async () => {
  const fixture = packageFixture(); fixture.manifest.archive.sha256 = "0".repeat(64);
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    if (String(input).endsWith("manifest.json")) return Response.json(fixture.manifest);
    const data = readFileSync(fixture.archive);
    return new Response(data, { headers: { "Content-Length": String(data.length) } });
  });
  const service = new GachaResourceService(fixture.data, "https://resource.example/manifest.json");
  await expect(service.install()).rejects.toMatchObject({ code: "gacha_resource_hash_mismatch" });
  expect(service.status().state).toBe("missing");
});

function packageFixture() {
  const root = mkdtempSync(join(tmpdir(), "mhg-gacha-resource-")); roots.push(root);
  const payload = join(root, "payload"), data = join(root, "data"), file = `images/${"a".repeat(64)}.img`;
  mkdirSync(join(payload, "images"), { recursive: true }); writeFileSync(join(payload, file), "fixture-image");
  const catalog = {
    schema_version: 2, version: "fixture-1", metadata_revision: "fixture-revision",
    items: { "10000096": ["阿蕾奇诺", "角色", 5, file] },
    character_assets: {
      avatars: { "10000089": file }, weapons: { "11513": file },
      reliquaries: { "95533": file }, skills: { "10892": file }, talents: { "891": file },
    },
    events: [{ id: "event", version: "4.6", gacha_type: "301", name: "炉边烬影",
      started_at: "2024-04-24T06:00:00+08:00", ended_at: "2024-05-14T17:59:00+08:00",
      orange_up: ["阿蕾奇诺"], purple_up: [], banner_file: file, updated_at: "2024-05-14T17:59:00+08:00" }],
  };
  writeFileSync(join(payload, "catalog.json"), JSON.stringify(catalog));
  const files = Object.fromEntries(["catalog.json", file].map((name) => [name, digest(join(payload, name))]));
  writeFileSync(join(payload, "mhg-manifest.json"), JSON.stringify({ files }));
  const archive = join(root, "gacha-history.zip");
  const zipped = spawnSync("/usr/bin/zip", ["-X", "-q", archive, "catalog.json", "mhg-manifest.json", file], { cwd: payload });
  if (zipped.status !== 0) throw new Error("测试资源打包失败");
  const size = readFileSync(archive).length;
  return { root, data, archive, file, manifest: { schema_version: 1, version: "fixture-1", archive: { url: "gacha-history.zip", size, sha256: digest(archive) } } };
}

function digest(path: string): string { return createHash("sha256").update(readFileSync(path)).digest("hex"); }
function record() { return { id: "1", uid: "100000001", gacha_type: "301", uigf_gacha_type: "301", item_id: "10000096", name: "", item_type: "", rank: 0, time: "2026-01-01T00:00:00Z" }; }
function character() { return {
  uid: "100000001", avatar_id: "10000089", name: "芙宁娜", element: "Hydro", level: 90,
  rarity: 5, constellation: 1, fetter: 10, weapon_name: "静水流涌之辉", weapon_level: 90,
  icon_url: "https://remote/avatar.png", updated_at: "2026-01-01T00:00:00Z",
  payload: {
    weapon: { id: 11513, icon: "https://remote/weapon.png" },
    relics: [{ id: 95533, icon: "https://remote/relic.png" }],
    skills: [{ skill_id: 10892, icon: "https://remote/skill.png" }],
  },
}; }
