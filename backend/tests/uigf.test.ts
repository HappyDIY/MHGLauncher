import { describe, expect, test } from "vitest";
import { AppError } from "../src/core/errors";
import { exportUIGF, importUIGF } from "../src/services/uigf";

const value = (version = "v4.2") => ({ info: { version }, hk4e: [{ uid: 100000001, list: [{ id: 10, uigf_gacha_type: 301, gacha_type: 400, item_id: 100, time: "2026-01-02 03:04:05", name: "角色", item_type: "角色", rank_type: 5 }] }] });
describe("UIGF", () => {
  test.each(["v4.0", "v4.1", "v4.2"])("导入 %s", (version) => expect(importUIGF(value(version))[0]).toMatchObject({ id: "10", uigf_gacha_type: "301" }));
  test("导入旧版", () => expect(importUIGF({ info: { uid: "1", uigf_version: "v3.0" }, list: value().hk4e[0]?.list }).length).toBe(1));
  test("拒绝空文件", () => expect(() => importUIGF({ info: { version: "v4.2" }, hk4e: [] })).toThrow(AppError));
  test("拒绝无效卡池", () => { const payload = value(); if (payload.hk4e[0]?.list[0]) payload.hk4e[0].list[0].gacha_type = 999; expect(() => importUIGF(payload)).toThrow("记录字段无效"); });
  test("按 UID 推导时区", () => expect((exportUIGF("600000001", importUIGF(value())).hk4e as { timezone: number }[])[0]?.timezone).toBe(-5));
  test("导出时间格式稳定", () => expect(JSON.stringify(exportUIGF("1", importUIGF(value())))).toContain("2026-01-02 03:04:05"));
});
