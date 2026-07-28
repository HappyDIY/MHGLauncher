import { expect, test, vi } from "vitest";
import type { GameCharacter } from "../src/core/models";
import type { Catalog } from "../src/services/gacha-resource-catalog";
import { localizeCharacter } from "../src/services/character-resource-enrichment";

const catalog = {
  schema_version: 2, version: "fixture", metadata_revision: "fixture",
  items: {}, events: [],
  character_assets: {
    avatars: { "10000089": "images/avatar.img" },
    weapons: { "11513": "images/weapon.img" },
    reliquaries: { "95533": "images/relic.img" },
    skills: { "10892": "images/skill.img" },
    talents: { "891": "images/talent.img" },
  },
} as Catalog;

test("旧版角色资料覆盖已知插图并代理其他米游社图片", () => {
  const endpoint = (name: string) => `/local/${name}`;
  const cached = vi.fn((remote?: string | null) => remote ? `/cache/${remote.split("/").at(-1)}` : null);
  const result = localizeCharacter(character(), catalog, endpoint, cached);
  expect(result).toMatchObject({
    icon_url: "/local/images/avatar.img",
    payload: {
      weapon: { icon: "/local/images/weapon.img" },
      relics: [{ icon: "/local/images/relic.img" }],
      skills: [{ icon: "/local/images/skill.img" }],
      constellations: [{ icon: "/local/images/talent.img" }],
      profile: { image: "/cache/profile.png" },
    },
  });
  expect(cached).toHaveBeenCalled();
});

test("无旧版目录时仅保留可代理图片", () => {
  const result = localizeCharacter(
    character(), undefined, (name) => name,
    (remote) => remote?.includes("mihoyo") ? "/cache/image.img" : null,
  );
  expect(result.icon_url).toBe("/cache/image.img");
  expect((result.payload as { profile: { image: string } }).profile.image).toBe("/cache/image.img");
});

function character(): GameCharacter {
  return {
    uid: "100000001", avatar_id: "10000089", name: "芙宁娜", element: "Hydro",
    level: 90, rarity: 5, constellation: 1, fetter: 10,
    weapon_name: "静水流涌之辉", weapon_level: 90,
    icon_url: "https://act-webstatic.mihoyo.com/avatar.png", updated_at: "2026-01-01T00:00:00Z",
    payload: {
      weapon: { id: 11513, icon: "https://act-webstatic.mihoyo.com/weapon.png" },
      relics: [{ id: 95533, icon: "https://act-webstatic.mihoyo.com/relic.png" }],
      skills: [{ skill_id: 10892, icon: "https://act-webstatic.mihoyo.com/skill.png" }],
      constellations: [{ id: 891, icon: "https://act-webstatic.mihoyo.com/talent.png" }],
      profile: { image: "https://act-webstatic.mihoyo.com/profile.png" },
    },
  };
}
