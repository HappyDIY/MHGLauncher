import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { WishRecord } from "../core/models";
import type { ImageCache } from "./images";

type Metadata = [name: string, type: string, rank: number, icon?: string];
let cache: Record<string, Metadata> | undefined;
let names: Map<string, [string, Metadata]> | undefined;

function all(): Record<string, Metadata> {
  cache ??= JSON.parse(readFileSync(join(process.cwd(), "src/mhglauncher/data/gacha_items.json"), "utf8")) as Record<string, Metadata>;
  return cache;
}

function remote(meta: Metadata): string {
  if (!meta[3]) return "";
  const avatar = meta[1] === "角色";
  const icon = avatar ? meta[3].replace("UI_AvatarIcon_", "UI_Gacha_AvatarIcon_") : meta[3].replace("UI_", "UI_Gacha_");
  return `https://api.snaphutaorp.org/static/raw/${avatar ? "GachaAvatarIcon" : "GachaEquipIcon"}/${icon}.png`;
}

export function enrich(record: WishRecord, images?: ImageCache): WishRecord {
  let id = record.item_id;
  let meta = all()[id];
  if (!meta && record.name) {
    names ??= new Map(Object.entries(all()).map(([key, value]) => [value[0], [key, value]]));
    const match = names.get(record.name);
    if (match) [id, meta] = match;
  }
  if (!meta) return { ...record, icon_url: record.icon_url ?? null };
  const url = remote(meta);
  if (images && url) void images.ensure(url).catch(() => undefined);
  return {
    ...record, item_id: id, name: record.name || meta[0], item_type: record.item_type || meta[1],
    rank: record.rank || meta[2], icon_url: images ? images.localURL(url) : url,
  };
}
