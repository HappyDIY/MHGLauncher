import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { GachaEvent } from "../core/models";

type ItemMetadata = [name: string, type: string, rank: number, icon?: string];
interface RawGachaEvent {
  Name: string;
  Version: string;
  Order: number;
  Banner: string;
  From: string;
  To: string;
  Type: number;
  UpOrangeList: number[];
  UpPurpleList: number[];
}

let cache: GachaEvent[] | undefined;

export function bundledGachaEvents(): GachaEvent[] {
  cache ??= load();
  return cache;
}

function load(): GachaEvent[] {
  const root = join(process.cwd(), "src/mhglauncher/data");
  const events = JSON.parse(readFileSync(join(root, "gacha_events.json"), "utf8")) as RawGachaEvent[];
  const items = JSON.parse(readFileSync(join(root, "gacha_items.json"), "utf8")) as Record<string, ItemMetadata>;
  return events.map((value) => ({
    id: `metadata:${value.Type}:${value.From}:${value.Order}`,
    version: value.Version,
    gacha_type: String(value.Type),
    name: value.Name,
    started_at: value.From,
    ended_at: value.To,
    orange_up: names(value.UpOrangeList, items),
    purple_up: names(value.UpPurpleList, items),
    banner_url: value.Banner || null,
    updated_at: value.To,
  }));
}

function names(ids: number[], items: Record<string, ItemMetadata>): string[] {
  return ids.map((id) => items[String(id)]?.[0] ?? String(id));
}
