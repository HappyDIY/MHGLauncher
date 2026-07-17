import { afterEach, describe, expect, test, vi } from "vitest";
import { equalToken, verifyGachaUrl } from "../src/auth";
import { fail } from "../src/http";

afterEach(() => { vi.restoreAllMocks(); });

describe("云端认证工具", () => {
  test("令牌比较保持稳定", () => {
    expect(equalToken("abc", "abc")).toBe(true);
    expect(equalToken("abc", "abd")).toBe(false);
    expect(equalToken("abc", "abcd")).toBe(false);
  });

  test("抽卡 URL 仅允许官方域名", async () => {
    const fetch = vi.spyOn(globalThis, "fetch");
    await expect(verifyGachaUrl("https://notmihoyo.com/gacha?authkey=x")).rejects.toMatchObject({ code: "gacha_url_invalid" });
    await expect(verifyGachaUrl("http://public-operation-hk4e.mihoyo.com/gacha?authkey=x")).rejects.toMatchObject({ code: "gacha_url_invalid" });
    expect(fetch).not.toHaveBeenCalled();
  });

  test("UID 仅采用官方响应且禁止重定向", async () => {
    const fetch = vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({ retcode: 0, data: {
	      uid: "100000002", list: [{ uid: "100000002", id: "1", gacha_type: "301", item_id: "", name: "角色", item_type: "角色", rank_type: "5", time: "2026-01-01 08:00:00" }],
    } }));
    const result = await verifyGachaUrl("https://public-operation-hk4e.mihoyo.com/gacha?authkey=x&uid=100000001");
    expect(result.uid).toBe("100000002");
    expect(fetch.mock.calls[0]?.[1]).toMatchObject({ redirect: "error" });
	    const request = new URL(String(fetch.mock.calls[0]?.[0]));
	    expect(Object.fromEntries(request.searchParams)).toMatchObject({ gacha_type: "301", size: "20", end_id: "0" });
  });

  test("内部异常不会把原文返回客户端", async () => {
    const response = fail(new Error("postgres password=secret"));
    expect(await response.json()).toEqual({ code: "internal_error", message: "云端服务异常" });
  });
});
