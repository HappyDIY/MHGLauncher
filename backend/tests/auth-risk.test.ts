import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import { AppError } from "../src/core/errors";
import { LiveProvider } from "../src/providers/live";
import { qrConfirmedPayload } from "../src/providers/qr";

const roots: string[] = [];

function liveProvider(): LiveProvider {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-auth-risk-")); roots.push(dataDir);
  return new LiveProvider({ dataDir, databasePath: join(dataDir, "test.db"), apiToken: "", providerMode: "live",
    fixtureDir: join(process.cwd(), "fixtures"), requestTimeout: 30_000, downloadWorkers: 4, socketPath: join(dataDir, "test.sock") });
}

afterEach(() => { vi.restoreAllMocks(); for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

describe("登录风控兼容", () => {
  test("短信验证码 Aigis 会话要求 Geetest 并按源项目头重发", async () => {
    const provider = liveProvider(), risk = JSON.stringify({
      session_id: "risk-session", mmt_type: 1,
      data: JSON.stringify({ gt: "gt-token", challenge: "server-challenge" }),
    });
    let aigis = "";
    vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
      aigis = new Headers(init?.headers).get("x-rpc-aigis") ?? "";
      if (!aigis) return Response.json({ retcode: -3101, message: "risk" }, { headers: { "X-Rpc-Aigis": risk } });
      return Response.json({ retcode: 0, data: { action_type: "login", countdown: 60 } }, { headers: { "X-Rpc-Aigis": "verified-aigis" } });
    });

    await expect(provider.createMobileCaptcha("13800138000")).rejects.toMatchObject({
      code: "verification_required",
      details: { gt: "gt-token", challenge: "server-challenge", session_id: "risk-session" },
    });
    const session = await provider.verifyMobileCaptcha("13800138000", "risk-session", "client-challenge", "validate-token");
    const [sessionId, encoded] = aigis.split(";");
    expect(session).toMatchObject({ action_type: "login", aigis: "verified-aigis" });
    expect(sessionId).toBe("risk-session");
    expect(JSON.parse(Buffer.from(encoded ?? "", "base64").toString("utf8"))).toEqual({
      geetest_challenge: "client-challenge",
      geetest_validate: "validate-token",
      geetest_seccode: "validate-token|jordan",
    });
  });

  test("二维码确认必须带 token_type 1", () => {
    expect(() => qrConfirmedPayload({ status: "Confirmed", payload: { user_info: { aid: "1" }, tokens: [{ token_type: 2, token: "ltoken" }] } }))
      .toThrow(AppError);
    expect(qrConfirmedPayload({ status: "Confirmed", payload: { user_info: { aid: "1" }, tokens: [{ token_type: 1, token: "stoken" }] } }).token)
      .toBe("stoken");
  });

  test("已确认二维码不会被后续过期轮询降级", async () => {
    const provider = liveProvider();
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url.includes("createQRLogin")) return Response.json({ retcode: 0, data: { ticket: "ticket", url: "https://example.invalid/qr" } });
      if (url.includes("queryQRLoginStatus")) return Response.json({ retcode: 0, data: { status: "Confirmed", payload: {
        user_info: { aid: "10001", mid: "mid-1", account_name: "旅行者" },
        tokens: [{ token_type: 1, token: "stoken-value" }],
      } } });
      return Response.json({ retcode: 0, data: { cookie_token: "cookie-token", uid: "10001" } });
    });
    const created = await provider.createQRSession();
    await provider.queryQRSession(created.id);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => Response.json({ retcode: 0, data: { status: "Expired" } }));
    expect((await provider.queryQRSession(created.id))[0].status).toBe("confirmed");
  });

  test("二维码过期 retcode 只更新会话状态", async () => {
    const provider = liveProvider();
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("createQRLogin")) return Response.json({ retcode: 0, data: { ticket: "ticket", url: "https://example.invalid/qr" } });
      return Response.json({ retcode: -3501, message: "Expired", data: null });
    });
    const created = await provider.createQRSession();
    const [expired, identity] = await provider.queryQRSession(created.id);
    expect(expired.status).toBe("expired");
    expect(identity).toBeNull();
  });
});
