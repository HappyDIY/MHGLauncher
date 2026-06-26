import { expect, test } from "vitest";
import type { WishRecord } from "../src/core/models";
import { banner } from "../src/services/wish-statistics";

const images = { localURL: (value: string) => value, ensure: async () => undefined } as never;
const record = (id: string, rank: number, itemId = "", type = "301"): WishRecord => ({ id, uid: "1", gacha_type: type, uigf_gacha_type: type, item_id: itemId, name: id, item_type: "", rank, time: `2026-01-01T00:00:0${id}` });
test("统计保底距离", () => { const value = banner("1", "301", [record("1", 3), record("2", 5), record("3", 3)], images); expect(value.five_star_items[0]?.pity).toBe(2); expect(value.last_pity).toBe(1); });
test("武器池保底为 80", () => expect(banner("1", "302", [], images).guarantee_threshold).toBe(80));
test("百分比保留四位", () => expect(banner("1", "301", [record("1", 5), record("2", 3), record("3", 3)], images).five_star_percent).toBe(0.3333));
test("四星重置紫色保底", () => expect(banner("1", "301", [record("1", 3), record("2", 4), record("3", 3)], images).last_purple_pity).toBe(1));

test("限定池小保底不歪率排除大保底", () => {
  // 抽取序列（旧→新）：3★、限定五星、限定五星、3★、常驻五星(歪)、限定五星(大保底)
  // 小保底尝试：前两颗限定均在前一颗为 UP 时命中（smallWin=2），第四颗歪（smallLose=1），
  // 末颗限定因前一颗歪而触发大保底，不计入分母。
  const value = banner("1", "301", [
    record("1", 3, "", "301"),
    record("2", 5, "10000089", "301"), // 小保底命中
    record("3", 5, "10000089", "301"), // 小保底命中
    record("4", 3, "", "301"),
    record("5", 5, "10000003", "301"), // 歪常驻
    record("6", 5, "10000089", "301"), // 大保底（不计入）
  ], images);
  expect(value.small_guarantee_win_rate).toBe(0.6667);
  expect(value.average_up_pity).toBeCloseTo((2 + 1 + 1) / 3, 2);
});

test("常驻池不计算限定指标", () => {
  const value = banner("1", "200", [
    record("1", 5, "10000003", "200"), record("2", 5, "10000089", "200"),
  ], images);
  expect(value.average_up_pity).toBe(0);
  expect(value.small_guarantee_win_rate).toBe(0);
});
