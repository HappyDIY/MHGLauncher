import { afterEach, describe, expect, test, vi } from "vitest";
import { equalToken, verifyGachaUrl } from "../src/auth";

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
    expect(fetch).not.toHaveBeenCalled();
  });
});
