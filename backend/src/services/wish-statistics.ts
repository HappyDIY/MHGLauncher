import type { WishRecord } from "../core/models";
import type { ImageCache } from "./images";
import { enrich } from "./metadata";

interface BannerItem {
  name: string; item_id: string; item_type: string; rank: number; icon_url?: string | null;
  pull_number: number; pity: number; time: string;
}
export interface BannerDetail {
  uid: string; gacha_type: string; total: number; time_from: string | null; time_to: string | null;
  five_star_count: number; four_star_count: number; three_star_count: number;
  five_star_percent: number; four_star_percent: number; three_star_percent: number;
  max_pity: number; min_pity: number; average_pity: number; last_pity: number;
  last_purple_pity: number; guarantee_threshold: number; five_star_items: BannerItem[]; four_star_items: BannerItem[];
}

const rounded = (value: number, digits: number): number => Number(value.toFixed(digits));

export function banner(uid: string, type: string, records: WishRecord[], images: ImageCache): BannerDetail {
  let orange = 0, purple = 0, three = 0, four = 0, five = 0, max = 0, min = 0;
  const distances: number[] = [], oranges: BannerItem[] = [], purples: BannerItem[] = [];
  records.forEach((raw, index) => {
    orange += 1; purple += 1;
    const item = enrich(raw, images);
    if (item.rank === 5) {
      five += 1; distances.push(orange); max = Math.max(max, orange); min = min ? Math.min(min, orange) : orange;
      oranges.push(output(item, index + 1, orange)); orange = 0; purple = 0;
    } else if (item.rank === 4) {
      four += 1; purples.push(output(item, index + 1, purple)); purple = 0;
    } else if (item.rank === 3) three += 1;
  });
  const total = records.length;
  return {
    uid, gacha_type: type, total, time_from: records[0]?.time ?? null, time_to: records.at(-1)?.time ?? null,
    five_star_count: five, four_star_count: four, three_star_count: three,
    five_star_percent: rounded(five / (total || 1), 4), four_star_percent: rounded(four / (total || 1), 4),
    three_star_percent: rounded(three / (total || 1), 4), max_pity: max, min_pity: min,
    average_pity: rounded(distances.reduce((a, b) => a + b, 0) / (distances.length || 1), 2),
    last_pity: orange, last_purple_pity: purple, guarantee_threshold: type === "302" ? 80 : 90,
    five_star_items: oranges.reverse(), four_star_items: purples.reverse(),
  };
}

function output(item: WishRecord, pull_number: number, pity: number): BannerItem {
  return { name: item.name, item_id: item.item_id, item_type: item.item_type, rank: item.rank, icon_url: item.icon_url, pull_number, pity, time: item.time };
}
