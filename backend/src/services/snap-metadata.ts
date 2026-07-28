import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";
import type { AchievementGoalMetadata, AchievementMetadata } from "./achievement-metadata";
import { parseAchievementMetadata } from "./achievement-metadata";

const fileName = z.string().regex(/^[A-Za-z0-9_]{1,128}$/);
const itemBase = {
  Id: z.number().int().nonnegative(), Name: z.string(), Icon: fileName,
};
const itemSchema = z.object({
  ...itemBase, RankLevel: z.number().int().min(1).max(5),
}).passthrough();
const avatarSchema = z.object({
  ...itemBase,
  Quality: z.number().int().min(1).max(999),
  SkillDepot: z.object({
    Skills: z.array(z.object({ Id: z.number().int(), Icon: fileName }).passthrough()).default([]),
    Talents: z.array(z.object({ Id: z.number().int(), Icon: fileName }).passthrough()).default([]),
  }).passthrough(),
}).passthrough();
const relicSchema = z.object({
  Ids: z.array(z.number().int()).max(16), Icon: fileName,
}).passthrough();
const eventSchema = z.object({
  Name: z.string(), Version: z.string(), Order: z.number().int(), Banner: z.string().url(),
  From: z.string(), To: z.string(), Type: z.number().int(),
  UpOrangeList: z.array(z.number().int()).max(1_000), UpPurpleList: z.array(z.number().int()).max(1_000),
}).passthrough();

interface SnapItem {
  name: string; kind: "角色" | "武器"; rank: number; icon: string; digest: string;
}
interface SnapEvent {
  name: string; version: string; order: number; banner: string; from: string; to: string;
  type: number; orange: number[]; purple: number[];
}
export interface SnapAssets {
  avatars: Record<string, [string, string]>;
  weapons: Record<string, [string, string]>;
  reliquaries: Record<string, [string, string]>;
  skills: Record<string, [string, string]>;
  talents: Record<string, [string, string]>;
}
export interface MetadataSnapshot {
  oid: string; activatedAt: string; items: Record<string, SnapItem>; events: SnapEvent[];
  assets: SnapAssets; achievements: AchievementMetadata[]; goals: AchievementGoalMetadata[];
}

export function readSnapMetadata(root: string, oid: string): MetadataSnapshot {
  const chs = join(root, "Genshin", "CHS");
  const meta = json<Record<string, string>>(join(chs, "Meta.json"));
  const weapons = z.array(itemSchema).max(20_000).parse(json(join(chs, "Weapon.json")));
  const relics = z.array(relicSchema).max(20_000).parse(json(join(chs, "Reliquary.json")));
  const events = z.array(eventSchema).max(10_000).parse(json(join(chs, "GachaEvent.json")));
  const assets: SnapAssets = { avatars: {}, weapons: {}, reliquaries: {}, skills: {}, talents: {} };
  const items: Record<string, SnapItem> = {};
  for (const weapon of weapons) {
    const digest = meta.Weapon!; items[String(weapon.Id)] = { name: weapon.Name, kind: "武器", rank: weapon.RankLevel, icon: weapon.Icon, digest };
    assets.weapons[String(weapon.Id)] = [weapon.Icon, digest];
  }
  for (const relic of relics) for (const id of relic.Ids) assets.reliquaries[String(id)] = [relic.Icon, meta.Reliquary!];
  const avatarDir = join(chs, "Avatar");
  for (const name of readdirSync(avatarDir).filter((value) => value.endsWith(".json")).sort()) {
    const avatar = avatarSchema.parse(json(join(avatarDir, name)));
    const digest = meta[`Avatar/${name.slice(0, -5)}`]!;
    items[String(avatar.Id)] = { name: avatar.Name, kind: "角色", rank: avatar.Quality >= 5 ? 5 : avatar.Quality, icon: avatar.Icon, digest };
    assets.avatars[String(avatar.Id)] = [avatar.Icon, digest];
    for (const skill of avatar.SkillDepot.Skills) assets.skills[String(skill.Id)] = [skill.Icon, digest];
    for (const talent of avatar.SkillDepot.Talents) assets.talents[String(talent.Id)] = [talent.Icon, digest];
  }
  return {
    oid, activatedAt: new Date().toISOString(), items, assets,
    events: events.map((value) => ({
      name: value.Name, version: value.Version, order: value.Order, banner: value.Banner,
      from: value.From, to: value.To, type: value.Type, orange: value.UpOrangeList, purple: value.UpPurpleList,
    })),
    achievements: parseAchievementMetadata(readFileSync(join(chs, "Achievement.json"), "utf8"), "achievements"),
    goals: parseAchievementMetadata(readFileSync(join(chs, "AchievementGoal.json"), "utf8"), "goals"),
  };
}

function json<T = unknown>(path: string): T {
  return JSON.parse(readFileSync(path, "utf8")) as T;
}
