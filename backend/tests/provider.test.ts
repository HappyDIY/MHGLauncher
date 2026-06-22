import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { FixtureProvider } from "../src/providers/fixture";
import { cookies, sign } from "../src/providers/signing";
import { normalizeBuild } from "../src/providers/provider";
import { AppError, errorResponse } from "../src/core/errors";

const provider = (): FixtureProvider => new FixtureProvider(join(process.cwd(), "fixtures"));
describe("Provider 契约", () => {
  test("创建二维码", async () => expect((await provider().createQRSession()).status).toBe("created"));
  test("二维码首次轮询为已扫描", async () => { const value = provider(), session = await value.createQRSession(); expect((await value.queryQRSession(session.id))[0].status).toBe("scanned"); });
  test("二维码第二次轮询带身份", async () => { const value = provider(), session = await value.createQRSession(); await value.queryQRSession(session.id); expect((await value.queryQRSession(session.id))[1]?.aid).toBe("10001"); });
  test("过滤为原神角色", async () => expect((await provider().getRoles("x"))[0]?.region).toBe("cn_gf01"));
  test("读取构建 fixture", async () => expect((await provider().getBuild()).version).toBe("5.8.0"));
  test("读取祈愿 fixture", async () => { for await (const page of provider().wishes("x", (await provider().getRoles("x"))[0]!, {})) expect(page).toHaveLength(2); });
  test("读取便笺 fixture", async () => expect((await provider().getDailyNote("x", (await provider().getRoles("x"))[0]!)).max_resin).toBe(200));
  test("验证 fixture 返回挑战", async () => expect(await provider().verifyNoteChallenge("x", "c", "v")).toBe("fixture-xrpc-challenge"));
  test("解析 Cookie", () => expect(cookies("a=1; b=2").get("b")).toBe("2"));
  test("DS 签名包含三段", () => expect(sign("x4").split(",")).toHaveLength(3));
  test("领域错误保持统一响应", async () => expect(await errorResponse(new AppError("x", "错误", 409)).json()).toEqual({ code: "x", message: "错误", details: {} }));
  test("构建模型填充默认集合", () => expect(normalizeBuild({ version: "1" }).assets).toEqual([]));
});
