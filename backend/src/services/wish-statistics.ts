import type { WishRecord } from "../core/models";
import type { GachaResourceService } from "./gacha-resources";
import { isStandardFiveStar } from "./wish-standard-items";

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
  // 限定池专属：每个限定五星所需的原石数量依据平均 UP 出金抽数推算；常驻/新手池为 0。
  average_up_pity: number;
  // 限定池专属：小保底不歪率（排除大保底后的 50/50 胜率）；常驻/新手池为 0。
  small_guarantee_win_rate: number;
}

const rounded = (value: number, digits: number): number => Number(value.toFixed(digits));
const LIMITED_TYPES = new Set(["301", "302"]);

export function banner(uid: string, type: string, records: WishRecord[], resources: Pick<GachaResourceService, "enrich">): BannerDetail {
  let orange = 0, purple = 0, three = 0, four = 0, five = 0, max = 0, min = 0;
  let lastUpOrange = 0, smallWin = 0, smallLose = 0;
  let prevIsUp = true; // 第一颗五星之前视为已中，避免首颗即限定被误判为大保底
  const distances: number[] = [], upCycles: number[] = [], oranges: BannerItem[] = [], purples: BannerItem[] = [];
  const limited = LIMITED_TYPES.has(type);
  records.forEach((raw, index) => {
    orange += 1; purple += 1; lastUpOrange += 1;
    const item = resources.enrich(raw);
    if (item.rank === 5) {
      five += 1; distances.push(orange); max = Math.max(max, orange); min = min ? Math.min(min, orange) : orange;
      const isUp = limited && !isStandardFiveStar(item.item_id);
      if (limited) {
        if (isUp) {
          upCycles.push(lastUpOrange);
          // 上一颗非 UP（歪）时本次为触发大保底，不计入小保底统计；
          // 上一颗已为 UP 时本次为正常小保底 50/50 命中。
          if (prevIsUp) smallWin += 1;
        } else if (prevIsUp) {
          // 上一颗已为 UP 时本次为小保底 50/50 失败（歪常驻）。
          smallLose += 1;
        }
        prevIsUp = isUp;
      }
      oranges.push(output(item, index + 1, orange)); orange = 0; purple = 0; lastUpOrange = 0;
    } else if (item.rank === 4) {
      four += 1; purples.push(output(item, index + 1, purple)); purple = 0;
    } else if (item.rank === 3) three += 1;
  });
  const total = records.length;
  const smallTry = smallWin + smallLose;
  return {
    uid, gacha_type: type, total, time_from: records[0]?.time ?? null, time_to: records.at(-1)?.time ?? null,
    five_star_count: five, four_star_count: four, three_star_count: three,
    five_star_percent: rounded(five / (total || 1), 4), four_star_percent: rounded(four / (total || 1), 4),
    three_star_percent: rounded(three / (total || 1), 4), max_pity: max, min_pity: min,
    average_pity: rounded(distances.reduce((a, b) => a + b, 0) / (distances.length || 1), 2),
    last_pity: orange, last_purple_pity: purple, guarantee_threshold: type === "302" ? 80 : 90,
    five_star_items: oranges.reverse(), four_star_items: purples.reverse(),
    average_up_pity: rounded(upCycles.reduce((a, b) => a + b, 0) / (upCycles.length || 1), 2),
    small_guarantee_win_rate: rounded(smallTry ? smallWin / smallTry : 0, 4),
  };
}

function output(item: WishRecord, pull_number: number, pity: number): BannerItem {
  return { name: item.name, item_id: item.item_id, item_type: item.item_type, rank: item.rank, icon_url: item.icon_url, pull_number, pity, time: item.time };
}
