import { beforeEach, describe, expect, test } from "vitest";
import { fixture, request } from "./helpers";
import { installGachaResourceFixture } from "./gacha-resource-fixture";
import { dispatch } from "../src/api/router";
describe("本地 API 契约", () => {
  beforeEach(() => fixture());

  test("拒绝错误令牌", async () => {
    const response = await request("GET", "/v1/account", undefined, "wrong");
    expect(response.status).toBe(401); expect(await response.json()).toMatchObject({ code: "unauthorized" });
  });

  test("二维码登录并同步角色", async () => {
    const created = await (await request("POST", "/v1/auth/qr-sessions", {})).json();
    expect(created.status).toBe("created");
    expect((await (await request("GET", `/v1/auth/qr-sessions/${created.id}`)).json()).session.status).toBe("scanned");
    const confirmed = await (await request("GET", `/v1/auth/qr-sessions/${created.id}`)).json();
    const response = await request("POST", "/v1/auth/commit", { transaction_id: confirmed.prepared_login.transaction_id });
    const value = await response.json(); expect(value.account.credential_ref).toBe("keychain:account:10001"); expect(value.roles[0].uid).toBe("100000001");
  });

  test("多账号保留当前账号与角色选择", async () => {
    await loginCookie("stuid=10001; stoken=1; mid=mid-1");
    await loginCookie("stuid=10002; stoken=2; mid=mid-2");
    expect((await (await request("GET", "/v1/accounts")).json()).map((value: { aid: string }) => value.aid)).toEqual(["10002", "10001"]);
    const selected = await (await request("POST", "/v1/account/select", { aid: "10001" })).json();
    expect(selected.account.selected).toBe(true);
    expect(selected.roles[0].uid).toBe("100000001");
    await request("DELETE", "/v1/account");
    expect((await (await request("GET", "/v1/account")).json()).aid).toBe("10002");
  });

  test("Cookie 与短信验证码登录归一为账号会话", async () => {
    const cookie = await (await request("POST", "/v1/auth/cookie-login", { credential: "stuid=10001; stoken=fixture; mid=fixture-mid" })).json();
    expect(cookie.identity.credential).toContain("stoken=fixture");
    expect((await (await request("POST", "/v1/auth/commit", { transaction_id: cookie.transaction_id })).json()).account.credential_ref).toBe("keychain:account:10001");
    const captcha = await (await request("POST", "/v1/auth/mobile-captcha", { mobile: "13800138000" })).json();
    expect(captcha.action_type).toBe("fixture-action");
    const verified = await (await request("POST", "/v1/auth/mobile-captcha/verification", {
      mobile: "13800138000", session_id: "fixture-session", challenge: "challenge", validate: "validate",
    })).json();
    expect(verified.aigis).toBe("fixture-aigis");
    const sms = await (await request("POST", "/v1/auth/mobile-login", { mobile: "13800138000", captcha: "123456", action_type: captcha.action_type })).json();
    expect(sms.identity.credential).toContain("stoken=fixture");
    expect(sms.roles[0].uid).toBe("100000001"); expect(sms.transaction_id).toBeTruthy();
  });

  test("游戏启动校验安装目录", async () => {
    const response = await request("POST", "/v1/game/launch", { install_path: "/tmp/mhg-missing-game" });
    expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ code: "game_not_installed" });
  });

  test("未登录账号返回 null", async () => expect(await (await request("GET", "/v1/account")).json()).toBeNull());
  test("参数校验保持前端错误契约", async () => {
    const response = await request("POST", "/v1/auth/mobile-captcha", { mobile: "invalid" });
    expect(response.status).toBe(422);
    expect(await response.json()).toMatchObject({ code: "validation_error", message: "请求参数无效" });
  });
  test("畸形、超限和包含未知字段的 JSON 使用稳定客户端错误", async () => {
    const malformed = await dispatch(new Request("http://local/v1/auth/mobile-captcha", {
      method: "POST", headers: { Authorization: "Bearer test-token", "Content-Type": "application/json" }, body: "{",
    }));
    expect(malformed.status).toBe(400); expect(await malformed.json()).toMatchObject({ code: "invalid_json" });
    const oversized = await dispatch(new Request("http://local/v1/auth/mobile-captcha", {
      method: "POST", headers: { Authorization: "Bearer test-token", "Content-Type": "application/json", "Content-Length": String(1024 * 1024 + 1) }, body: "{}",
    }));
    expect(oversized.status).toBe(413); expect(await oversized.json()).toMatchObject({ code: "request_too_large" });
    const stream = new ReadableStream<Uint8Array>({ start(controller) { controller.enqueue(new Uint8Array(1024 * 1024)); controller.enqueue(new Uint8Array([1])); controller.close(); } });
    const streamed = await dispatch(new Request("http://local/v1/auth/mobile-captcha", {
      method: "POST", headers: { Authorization: "Bearer test-token", "Content-Type": "application/json" }, body: stream, duplex: "half",
    } as RequestInit & { duplex: "half" }));
    expect(streamed.status).toBe(413);
    expect((await request("POST", "/v1/auth/mobile-captcha", { mobile: "13800138000", ignored: true })).status).toBe(422);
  });
  test("未知任务返回 404", async () => expect((await request("GET", "/v1/wishes/tasks/missing")).status).toBe(404));
  test("删除账号返回 204", async () => expect((await request("DELETE", "/v1/account")).status).toBe(204));
  test("同步旧端点已删除", async () => expect((await request("POST", "/v1/wishes/sync", { credential: "x" })).status).toBe(404));
  test("历史卡池插图端点需要鉴权", async () => expect((await request("GET", `/v1/gacha-resources/files/images/${"a".repeat(64)}.img`, undefined, "bad")).status).toBe(401));

  test("限速设置读写", async () => {
    const initial = await (await request("GET", "/v1/settings/speed-limit")).json();
    expect(initial.speed_limit_kb).toBe(0);
    await request("POST", "/v1/settings/speed-limit", { speed_limit_kb: 2048 });
    const updated = await (await request("GET", "/v1/settings/speed-limit")).json();
    expect(updated.speed_limit_kb).toBe(2048);
  });

  test("游戏状态包含预下载字段", async () => {
    const state = await (await request("GET", "/v1/game/status")).json();
    expect(state).toHaveProperty("predownload_version");
    expect(state).toHaveProperty("predownload_finished");
  });

  test("陪伴数据快照与旧端点一致", async () => {
    const payload = { info: { version: "v4.2" }, hk4e: [{ uid: "100000001", list: [
      { id: "10", uigf_gacha_type: "301", gacha_type: "301", item_id: "100", time: "2026-01-02 03:04:05", name: "角色", item_type: "角色", rank_type: "5" },
    ] }] };
    const task = await (await request("POST", "/v1/wishes/tasks/import", payload)).json();
    await waitForTask(task.id);
    const snapshot = await (await request("GET", "/v1/companion/snapshot?uid=100000001")).json();
    const wishes = await (await request("GET", "/v1/wishes?uid=100000001")).json();
    const statistics = await (await request("GET", "/v1/wishes/statistics?uid=100000001")).json();
    const details = await (await request("GET", "/v1/wishes/banner-statistics?uid=100000001")).json();
    expect(snapshot.wishes).toEqual(wishes);
    expect(snapshot.statistics).toEqual(statistics);
    expect(snapshot.banner_statistics).toEqual(details);
  });

  test("任务状态端点支持 revision 长轮询参数", async () => {
    const task = await (await request("POST", "/v1/wishes/tasks/import", { info: { version: "v4.2" }, hk4e: [{ uid: "100000001", list: [
      { id: "11", uigf_gacha_type: "301", gacha_type: "301", item_id: "100", time: "2026-01-02 03:04:05", name: "角色", item_type: "角色", rank_type: "5" },
    ] }] })).json();
    const snapshot = await (await request("GET", `/v1/wishes/tasks/${task.id}?after_revision=999&wait_ms=5`)).json();
    expect(snapshot).toHaveProperty("revision");
    expect(snapshot.id).toBe(task.id);
  });

	  test("空间检查返回必要字段", async () => {
	    const response = await request("GET", "/v1/game/space-check?kind=install&install_path=/tmp");
	    const info = await response.json();
	    expect(info).toHaveProperty("available");
	    expect(info).toHaveProperty("required");
	    expect(info).toHaveProperty("sufficient");
	  });

	  test("增值服务接口支持离线 fixture 数据", async () => {
	    const credential = "stuid=10001; stoken=fixture; mid=fixture-mid";
	    await loginCookie(credential);
	    const body = { credential };
	    const characters = await (await request("POST", "/v1/characters/refresh", body)).json();
	    expect(characters[0].name).toBe("芙宁娜");
	    expect(await (await request("GET", "/v1/gacha-resources/status")).json()).toMatchObject({ state: "missing", event_count: 0 });
	    expect((await request("GET", "/v1/gacha-events")).status).toBe(409);
      installGachaResourceFixture();
	    const events = await (await request("GET", "/v1/gacha-events")).json();
	    expect(events).toHaveLength(1);
	    expect(events[0].banner_url).toMatch(/^\/v1\/gacha-resources\/files\//);
	    expect(events[0].orange_up_icons["阿蕾奇诺"]).toMatch(/^\/v1\/gacha-resources\/files\//);
      const image = await request("GET", events[0].banner_url);
      expect(Buffer.from(await image.arrayBuffer()).toString()).toBe("fixture-image");
});

async function loginCookie(credential: string): Promise<void> {
  const prepared = await (await request("POST", "/v1/auth/cookie-login", { credential })).json();
  const response = await request("POST", "/v1/auth/commit", { transaction_id: prepared.transaction_id });
  expect(response.status).toBe(200);
}

	  test("成就档案支持保存与导出 UIAF", async () => {
	    const archive = await (await request("POST", "/v1/achievements/archives", { name: "主档案" })).json();
	    const saved = await (await request("POST", "/v1/achievements", { archive_id: archive.id, expected_revision: 0, items: [{ achievement_id: 84501, current: 0, status: 2, timestamp: 1_756_000_000 }] })).json();
	    expect(saved.revision).toBe(1);
	    expect((await request("POST", "/v1/achievements", { archive_id: archive.id, expected_revision: 0, items: [] })).status).toBe(409);
	    const imported = await (await request("POST", `/v1/achievements/import?archive_id=${archive.id}&expected_revision=1`, {
	      info: { uiaf_version: "v1.1" }, list: [{ id: 84502, current: 1, status: 3, timestamp: 1_756_000_001 }],
	    })).json();
	    expect(imported.revision).toBe(2);
	    expect((await request("POST", `/v1/achievements/import?archive_id=${archive.id}&expected_revision=1`, { list: [] })).status).toBe(409);
	    const items = await (await request("GET", `/v1/achievements?archive_id=${archive.id}`)).json();
	    expect(items[0].achievement_id).toBe(84501);
    const view = await (await request("GET", `/v1/achievements/view?archive_id=${archive.id}`)).json();
    expect(view.find((value: { achievement_id: number }) => value.achievement_id === 84501).status).toBe(2);
	    expect(view.find((value: { achievement_id: number }) => value.achievement_id === 84501).current).toBe(1);
    const goals = await (await request("GET", "/v1/achievements/goals")).json();
    expect(goals.length).toBeGreaterThan(0);
    expect([...view, ...goals].every((value: { icon_url: string | null }) => value.icon_url === null || value.icon_url.startsWith("https://"))).toBe(true);
    const exported = await (await request("GET", `/v1/achievements/export?archive_id=${archive.id}`)).json();
	    expect(exported.list[0].id).toBe(84501);
	  });

	  test("未配置时拒绝云同步且通知设置仍提供本地代理", async () => {
	    const credential = "stuid=10001; stoken=fixture; mid=fixture-mid";
	    await loginCookie(credential);
	    const cloudLogin = await request("POST", "/v1/cloud/login/account", { credential });
	    expect(cloudLogin.status).toBe(503);
	    expect(await cloudLogin.json()).toMatchObject({ code: "cloud_not_configured" });
	    const settings = await (await request("PUT", "/v1/notifications/settings", { daily_commission_enabled: true, daily_commission_time: "00:00" })).json();
	    expect(settings.daily_commission_enabled).toBe(true);
	    expect(settings).not.toHaveProperty("abyss_refresh_enabled");
	    expect(settings).not.toHaveProperty("theatre_refresh_enabled");
	    expect(settings).not.toHaveProperty("hard_refresh_enabled");
	    expect((await request("GET", "/v1/cycles/abyss?uid=100000001")).status).toBe(404);
	    expect((await request("POST", "/v1/cycles/abyss/refresh", { credential: "fixture" })).status).toBe(404);
	    expect((await request("POST", "/v1/cycles/abyss/upload", { uid: "100000001", token: "fixture", schedule_id: "old" })).status).toBe(404);
	  });

	  test("提醒时间只接受严格 HH:mm", async () => {
	    for (const value of ["abc", "24:00", "9:30", "23:60"]) expect((await request("PUT", "/v1/notifications/settings", { daily_commission_time: value })).status).toBe(422);
	    expect((await request("PUT", "/v1/notifications/settings", { daily_commission_time: "23:59" })).status).toBe(200);
	  });
	});

async function waitForTask(id: string): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const task = await (await request("GET", `/v1/wishes/tasks/${id}`)).json();
    if (task.status === "completed") return; if (task.status === "failed") throw new Error(`祈愿任务失败：${task.error_code} ${task.error}`);
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("等待祈愿任务完成超时");
}
