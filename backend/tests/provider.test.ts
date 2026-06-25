import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import { FixtureProvider } from "../src/providers/fixture";
import { LiveProvider } from "../src/providers/live";
import { cookies, sign } from "../src/providers/signing";
import { normalizeBuild } from "../src/providers/provider";
import { AppError, errorResponse } from "../src/core/errors";
import { decodeSophonManifest } from "../src/providers/sophon";

const provider = (): FixtureProvider => new FixtureProvider(join(process.cwd(), "fixtures"));
const roots: string[] = [];
function liveProvider(): LiveProvider {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-live-test-")); roots.push(dataDir);
  return new LiveProvider({ dataDir, databasePath: join(dataDir, "test.db"), apiToken: "", providerMode: "live",
    fixtureDir: join(process.cwd(), "fixtures"), requestTimeout: 30_000, downloadWorkers: 4, socketPath: join(dataDir, "test.sock") });
}
afterEach(() => { vi.restoreAllMocks(); for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });
describe("Provider 契约", () => {
  test("创建二维码", async () => expect((await provider().createQRSession()).status).toBe("created"));
  test("二维码首次轮询为已扫描", async () => { const value = provider(), session = await value.createQRSession(); expect((await value.queryQRSession(session.id))[0].status).toBe("scanned"); });
  test("二维码第二次轮询带身份", async () => { const value = provider(), session = await value.createQRSession(); await value.queryQRSession(session.id); expect((await value.queryQRSession(session.id))[1]?.aid).toBe("10001"); });
  test("过滤为原神角色", async () => expect((await provider().getRoles("x"))[0]?.region).toBe("cn_gf01"));
  test("读取构建 fixture", async () => expect((await provider().getBuild()).version).toBe("5.8.0"));
  test("读取祈愿 fixture", async () => { for await (const page of provider().wishes("x", (await provider().getRoles("x"))[0]!, {})) expect(page).toHaveLength(2); });
  test("读取便笺 fixture", async () => expect((await provider().getDailyNote("x", (await provider().getRoles("x"))[0]!)).max_resin).toBe(200));
  test("验证 fixture 返回挑战", async () => expect(await provider().verifyNoteChallenge("x", "c", "v")).toBe("fixture-xrpc-challenge"));
  test("fixture 返回游戏登录票据", async () => expect(await provider().createAuthTicket("x")).toBe("fixture-auth-ticket"));
  test("解析 Cookie 保留等号并忽略重复键", () => { const value = cookies("a=b=c; b=2; a=3"); expect(value.get("a")).toBe("b=c"); expect(value.get("b")).toBe("2"); });
  test("DS 签名包含三段", () => expect(sign("x4").split(",")).toHaveLength(3));
  test("扫码请求使用 HoyoPlay 设备标识", async () => {
    let headers: HeadersInit | undefined;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
      headers = init?.headers;
      return Response.json({ retcode: 0, data: { ticket: "ticket", url: "https://example.invalid/qr" } });
    });
    await liveProvider().createQRSession();
    const value = new Headers(headers);
    expect(value.get("user-agent")).toBe("HYPContainer/1.1.4.133");
    expect(value.get("x-rpc-app_id")).toBe("ddxf5dufpuyo");
    expect(value.get("x-rpc-client_type")).toBe("3");
    expect(value.get("x-rpc-device_id")).toMatch(/^[0-9a-z]{53}$/);
  });
  test("短信验证码请求往返 Aigis", async () => {
    let headers: HeadersInit | undefined;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
      headers = init?.headers;
      return Response.json({ retcode: 0, data: { action_type: "login", countdown: 60 } }, { headers: { "X-Rpc-Aigis": "risk-token" } });
    });
    const session = await liveProvider().createMobileCaptcha("13800138000");
    const value = new Headers(headers);
    expect(value.get("x-rpc-aigis")).toBe("");
    expect(value.get("x-rpc-app_id")).toBe("bll8iq97cem8");
    expect(session.aigis).toBe("risk-token");
  });
  test("Cookie 登录补齐 stoken 凭据", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      expect(String(input)).toContain("getCookieAccountInfoBySToken");
      expect(new Headers(init?.headers).get("cookie")).toContain("stoken=a=b");
      return Response.json({ retcode: 0, data: { cookie_token: "cookie-token", uid: "10001" } });
    });
    const identity = await liveProvider().identifyCredential("stuid=10001; stoken=a=b; mid=mid-1");
    expect(identity.credential).toContain("stoken=a=b");
    expect(identity.credential).toContain("cookie_token=cookie-token");
  });
  test("Cookie 登录票据换取 stoken", async () => {
    const urls: string[] = [];
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      urls.push(String(input));
      if (String(input).includes("getMultiTokenByLoginTicket")) {
        return Response.json({ retcode: 0, data: { list: [{ name: "stoken", token: "new-stoken" }] } });
      }
      return Response.json({ retcode: 0, data: { cookie_token: "cookie-token", uid: "10001" } });
    });
    const identity = await liveProvider().identifyCredential("login_ticket=ticket; login_uid=10001");
    expect(urls[0]).toContain("getMultiTokenByLoginTicket");
    expect(urls[1]).toContain("getCookieAccountInfoBySToken");
    expect(identity.credential).toContain("stoken=new-stoken");
  });
  test("实时便笺 5003 首次返回验证挑战", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("dailyNote")) return Response.json({ retcode: 5003, message: "", data: null });
      if (String(input).includes("createVerification")) return Response.json({ retcode: 0, data: { gt: "gt", challenge: "challenge" } });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    await expect(liveProvider().getDailyNote("stuid=10001; stoken=token", { uid: "100000001", region: "cn_gf01", nickname: "旅行者", level: 60, selected: true }))
      .rejects.toMatchObject({ code: "verification_required", status: 428, details: { gt: "gt", challenge: "challenge" } });
  });
  test("实时便笺验证后 10306 不再重复创建验证码", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("dailyNote")) return Response.json({ retcode: 10306, message: "", data: null });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    await expect(liveProvider().getDailyNote("stuid=10001; stoken=token", { uid: "100000001", region: "cn_gf01", nickname: "旅行者", level: 60, selected: true }, "old"))
      .rejects.toMatchObject({ code: "note_verification_failed", status: 429, details: { retcode: "10306" } });
  });
  test("实时便笺验证后仍 5003 返回账号风险提示", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("dailyNote")) return Response.json({ retcode: 5003, message: "", data: null });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    await expect(liveProvider().getDailyNote("stuid=10001; stoken=token", { uid: "100000001", region: "cn_gf01", nickname: "旅行者", level: 60, selected: true }, "verified"))
      .rejects.toMatchObject({ code: "note_risk_limited", status: 429, message: "当前账号存在风险，实时便笺暂无数据，请稍后重试或在米游社完成验证", details: { retcode: "5003" } });
  });
  test("实时便笺验证请求携带源项目挑战头", async () => {
    let headers: Headers | undefined;
    let body: unknown;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
      headers = new Headers(init?.headers);
      body = JSON.parse(String(init?.body));
      return Response.json({ retcode: 0, data: { challenge: "xrpc-challenge" } });
    });
    await expect(liveProvider().verifyNoteChallenge("stuid=10001; stoken=token", "challenge", "validate")).resolves.toBe("xrpc-challenge");
    expect(body).toEqual({ geetest_challenge: "challenge", geetest_validate: "validate", geetest_seccode: "validate|jordan" });
    expect(headers?.get("x-rpc-challenge_game")).toBe("2");
    expect(headers?.get("x-rpc-challenge_path")).toBe("/game_record/app/genshin/api/dailyNote");
  });
  test("创建游戏登录票据使用 HoyoPlay 头并返回 ticket", async () => {
    let url: string | undefined;
    let headers: HeadersInit | undefined;
    let body: unknown;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      url = String(input);
      headers = init?.headers;
      body = JSON.parse(String(init?.body));
      return Response.json({ retcode: 0, data: { ticket: "auth-ticket-value" } });
    });
    await expect(liveProvider().createAuthTicket("stuid=10001; stoken=token; mid=mid-1")).resolves.toBe("auth-ticket-value");
    expect(url).toContain("passport-api.mihoyo.com/account/ma-cn-verifier/app/createAuthTicketByGameBiz");
    const value = new Headers(headers);
    expect(value.get("user-agent")).toBe("HYPContainer/1.1.4.133");
    expect(value.get("x-rpc-app_id")).toBe("ddxf5dufpuyo");
    expect(value.get("x-rpc-client_type")).toBe("3");
    expect(value.get("cookie")).toContain("stoken=token");
    expect(body).toEqual({ game_biz: "hk4e_cn", mid: "mid-1", stoken: "token", uid: 10001 });
  });
  test("缺少 stoken 时拒绝创建游戏登录票据", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => Response.json({ retcode: 0, data: { ticket: "x" } }));
    await expect(liveProvider().createAuthTicket("stuid=10001; mid=mid-1")).rejects.toMatchObject({ code: "credential_invalid", status: 422 });
  });
  test("领域错误保持统一响应", async () => expect(await errorResponse(new AppError("x", "错误", 409)).json()).toEqual({ code: "x", message: "错误", details: {} }));
  test("构建模型填充默认集合", () => expect(normalizeBuild({ version: "1" }).assets).toEqual([]));
  test("Sophon 清单保留下划线字段", () => {
    const data = Buffer.from("Ci4KDFl1YW5TaGVuLmV4ZRIXCgpoYXNoX2NodW5rEgNkZWYYACAUKCogKioDYWJj", "base64");
    const asset = (decodeSophonManifest(data).assets as Record<string, unknown>[])[0];
    expect(asset).toMatchObject({ asset_name: "YuanShen.exe", asset_size: 42, asset_hash_md5: "abc" });
    expect((asset?.asset_chunks as Record<string, unknown>[])[0]).toMatchObject({ chunk_name: "hash_chunk", chunk_size: 20 });
  });
});
