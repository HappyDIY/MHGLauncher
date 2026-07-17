import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test, vi } from "vitest";
import type { GameCharacter } from "../src/core/models";
import { ImageResourceCache } from "../src/services/image-resource-cache";

const roots: string[] = [];
afterEach(() => {
  vi.restoreAllMocks();
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("账号特殊素材一次下载后始终使用本地文件", async () => {
  const root = mkdtempSync(join(tmpdir(), "mhg-image-cache-")); roots.push(root);
  const cache = new ImageResourceCache(root), remote = "https://act-webstatic.mihoyo.com/assets/special.png";
  const fetcher = vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(
    Buffer.from("89504e470d0a1a0a", "hex"), { headers: { "content-length": "8" } },
  ));
  await cache.ensureCharacters([character(remote)]);
  const local = cache.localURL(remote);
  expect(local).toMatch(/^\/v1\/gacha-resources\/cache\/[a-f0-9]{64}\.img$/);
  expect(cache.file(local!.split("/").at(-1)!)?.length).toBe(8);
  await cache.ensureCharacters([character(remote)]);
  expect(fetcher).toHaveBeenCalledTimes(1);
});

test("账号素材缓存拒绝非米游社来源", async () => {
  const root = mkdtempSync(join(tmpdir(), "mhg-image-cache-")); roots.push(root);
  const cache = new ImageResourceCache(root), fetcher = vi.spyOn(globalThis, "fetch");
  await cache.ensureCharacters([character("https://example.com/private.png")]);
  expect(fetcher).not.toHaveBeenCalled();
  expect(cache.localURL("https://example.com/private.png")).toBeNull();
});

function character(remote: string): GameCharacter {
  return {
    uid: "100000001", avatar_id: "10000005", name: "旅行者", element: "Geo",
    level: 90, rarity: 5, constellation: 0, fetter: 10,
    weapon_name: "无锋剑", weapon_level: 90, icon_url: remote,
    payload: { skills: [{ skill_id: 10077, icon: remote }] }, updated_at: "2026-01-01T00:00:00Z",
  };
}
