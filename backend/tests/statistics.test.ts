import { expect, test } from "vitest";
import type { WishRecord } from "../src/core/models";
import { banner } from "../src/services/wish-statistics";

const images = { localURL: (value: string) => value, ensure: async () => undefined } as never;
const record = (id: string, rank: number): WishRecord => ({ id, uid: "1", gacha_type: "301", uigf_gacha_type: "301", item_id: "", name: id, item_type: "", rank, time: `2026-01-01T00:00:0${id}` });
test("统计保底距离", () => { const value = banner("1", "301", [record("1", 3), record("2", 5), record("3", 3)], images); expect(value.five_star_items[0]?.pity).toBe(2); expect(value.last_pity).toBe(1); });
test("武器池保底为 80", () => expect(banner("1", "302", [], images).guarantee_threshold).toBe(80));
test("百分比保留四位", () => expect(banner("1", "301", [record("1", 5), record("2", 3), record("3", 3)], images).five_star_percent).toBe(0.3333));
test("四星重置紫色保底", () => expect(banner("1", "301", [record("1", 3), record("2", 4), record("3", 3)], images).last_purple_pity).toBe(1));
