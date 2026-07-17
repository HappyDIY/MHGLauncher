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
  // 与源项目一致：使用普通方形图标（AvatarIcon/EquipIcon），而非祈愿大立绘
  // （GachaAvatarIcon/GachaEquipIcon）。方形紧凑图标在小卡片中不会被裁切，
  // 也不留大量空白。
  const avatar = meta[1] === "角色";
  const icon = meta[3];
  return `https://api.snaphutaorp.org/static/raw/${avatar ? "AvatarIcon" : "EquipIcon"}/${icon}.png`;
}

function named(value: string): [string, Metadata] | undefined {
  names ??= new Map(Object.entries(all()).map(([key, metadata]) => [metadata[0], [key, metadata]]));
  return names.get(value);
}

export function iconURLs(values: string[], images?: ImageCache): Record<string, string> {
  const result: Record<string, string> = {};
  for (const value of values) {
    const meta = named(value)?.[1];
    if (!meta) continue;
    const url = remote(meta);
    if (url) result[value] = images ? images.localURL(url) : url;
  }
  return result;
}

export function enrich(record: WishRecord, images?: ImageCache): WishRecord {
  let id = record.item_id;
  let meta = all()[id];
  if (!meta && record.name) {
    const match = named(record.name);
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
