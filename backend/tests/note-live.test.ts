import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import { LiveProvider } from "../src/providers/live";

const roots: string[] = [];
function liveProvider(): LiveProvider {
  const dataDir = mkdtempSync(join(tmpdir(), "mhg-live-note-test-")); roots.push(dataDir);
  return new LiveProvider({ dataDir, databasePath: join(dataDir, "test.db"), apiToken: "", providerMode: "live",
    fixtureDir: join(process.cwd(), "fixtures"), requestTimeout: 30_000, downloadWorkers: 4, downloadSpeedLimitKB: 0, socketPath: join(dataDir, "test.sock") });
}
const role = { uid: "100000001", region: "cn_gf01", nickname: "旅行者", level: 60, selected: true };
const cookie = "account_id=10001; cookie_token=cookie-token; ltuid=10001; ltoken=ltoken-value";

afterEach(() => { vi.restoreAllMocks(); for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

describe("实时便笺 live 请求画像", () => {
  test("先访问战绩首页并使用 CookieToken/LToken", async () => {
    const urls: string[] = []; let noteHeaders: Headers | undefined, fpBody: Record<string, unknown> | undefined;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      urls.push(String(input));
      if (String(input).includes("dailyNote")) {
        noteHeaders = new Headers(init?.headers);
        return Response.json({ retcode: 0, data: { current_resin: 120, max_resin: 200, finished_task_num: 3, total_task_num: 4, expeditions: [{ status: "Finished" }], max_expedition_num: 5, transformer: { recovery_time: { reached: true } } } });
      }
      if (String(input).includes("device-fp")) fpBody = JSON.parse(String(init?.body));
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    const note = await liveProvider().getDailyNote(`stuid=10001; stoken=token; ${cookie}`, role);
    expect(urls[1]).toContain("/game_record/app/genshin/api/index?");
    expect(urls[2]).toContain("/game_record/app/genshin/api/dailyNote?");
    expect(note.current_resin).toBe(120);
    expect(noteHeaders?.get("cookie")).toBe("account_id=10001;cookie_token=cookie-token;ltoken=ltoken-value;ltuid=10001");
    expect(noteHeaders?.get("cookie")).not.toContain("stoken");
    expect(noteHeaders?.get("referer")).toBe("https://webstatic.mihoyo.com");
    expect(noteHeaders?.get("x-rpc-tool_verison")).toBe("v5.0.1-ys");
    expect(JSON.parse(String(fpBody?.ext_fields)).hostname).toBe("dg02-pool03-kvm87");
  });

  test("首页预热后仍 5003 才返回账号风险提示", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("dailyNote")) return Response.json({ retcode: 5003, message: "", data: null });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    await expect(liveProvider().getDailyNote(cookie, role))
      .rejects.toMatchObject({ code: "note_risk_limited", status: 429, details: { retcode: "5003" } });
  });

  test("战绩首页 1034 返回首页验证挑战", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("/api/index")) return Response.json({ retcode: 1034, message: "", data: null });
      if (String(input).includes("createVerification")) return Response.json({ retcode: 0, data: { gt: "index-gt", challenge: "index-challenge" } });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    await expect(liveProvider().getDailyNote(cookie, role)).rejects.toMatchObject({
      code: "verification_required", status: 428,
      details: { gt: "index-gt", challenge: "index-challenge", xrpc_challenge_path: "/game_record/app/genshin/api/index" },
    });
  });

  test("完成首页验证后继续请求便笺", async () => {
    const urls: string[] = []; let indexHeaders: Headers | undefined;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      urls.push(String(input));
      if (String(input).includes("/api/index")) indexHeaders = new Headers(init?.headers);
      if (String(input).includes("dailyNote")) return Response.json({ retcode: 0, data: { current_resin: 88, max_resin: 200, finished_task_num: 4, total_task_num: 4, expeditions: [], transformer: { recovery_time: { reached: false } } } });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    const note = await liveProvider().getDailyNote(cookie, role, "verified-index", "/game_record/app/genshin/api/index");
    expect(urls.some((url) => url.includes("dailyNote"))).toBe(true);
    expect(indexHeaders?.get("x-rpc-challenge")).toBe("verified-index");
    expect(note.current_resin).toBe(88);
  });

  test("dailyNote 1034 首次返回验证挑战", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("dailyNote")) return Response.json({ retcode: 1034, message: "", data: null });
      if (String(input).includes("createVerification")) return Response.json({ retcode: 0, data: { gt: "gt", challenge: "challenge" } });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    await expect(liveProvider().getDailyNote(cookie, role))
      .rejects.toMatchObject({ code: "verification_required", status: 428, details: { gt: "gt", challenge: "challenge", xrpc_challenge_path: "/game_record/app/genshin/api/dailyNote" } });
  });

  test("dailyNote 验证后仍 1034 提示验证失效", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("dailyNote")) return Response.json({ retcode: 1034, message: "", data: null });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    await expect(liveProvider().getDailyNote(cookie, role, "old", "/game_record/app/genshin/api/dailyNote"))
      .rejects.toMatchObject({ code: "note_verification_failed", status: 429, details: { retcode: "1034" } });
  });

  test("10306 重新返回验证挑战", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (String(input).includes("dailyNote")) return Response.json({ retcode: 10306, message: "", data: null });
      if (String(input).includes("createVerification")) return Response.json({ retcode: 0, data: { gt: "gt2", challenge: "challenge2" } });
      return Response.json({ retcode: 0, data: { device_fp: "fp" } });
    });
    await expect(liveProvider().getDailyNote(cookie, role, "old", "/game_record/app/genshin/api/dailyNote"))
      .rejects.toMatchObject({ code: "verification_required", status: 428, details: { gt: "gt2", challenge: "challenge2" } });
  });

  test("验证请求默认携带便笺路径，也可切换到首页路径", async () => {
    const paths: string[] = [];
    vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
      paths.push(new Headers(init?.headers).get("x-rpc-challenge_path") ?? "");
      return Response.json({ retcode: 0, data: { challenge: "xrpc-challenge" } });
    });
    await expect(liveProvider().verifyNoteChallenge(cookie, "challenge", "validate")).resolves.toBe("xrpc-challenge");
    await expect(liveProvider().verifyNoteChallenge(cookie, "challenge", "validate", "/game_record/app/genshin/api/index")).resolves.toBe("xrpc-challenge");
    expect(paths).toEqual(["/game_record/app/genshin/api/dailyNote", "/game_record/app/genshin/api/index"]);
  });
});
