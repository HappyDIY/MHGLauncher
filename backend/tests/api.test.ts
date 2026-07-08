import { beforeEach, describe, expect, test } from "vitest";
import { fixture, request } from "./helpers";

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
    const response = await request("POST", "/v1/auth/complete", { identity: confirmed.identity, credential_ref: "keychain:test" });
    const value = await response.json(); expect(value.account.credential_ref).toBe("keychain:test"); expect(value.roles[0].uid).toBe("100000001");
  });

  test("多账号保留当前账号与角色选择", async () => {
    const first = { aid: "10001", mid: "mid-1", nickname: "一号", credential: "stoken=1; mid=mid-1" };
    const second = { aid: "10002", mid: "mid-2", nickname: "二号", credential: "stoken=2; mid=mid-2" };
    await request("POST", "/v1/auth/complete", { identity: first, credential_ref: "keychain:account:10001" });
    await request("POST", "/v1/auth/complete", { identity: second, credential_ref: "keychain:account:10002" });
    expect((await (await request("GET", "/v1/accounts")).json()).map((value: { aid: string }) => value.aid)).toEqual(["10002", "10001"]);
    const selected = await (await request("POST", "/v1/account/select", { aid: "10001" })).json();
    expect(selected.account.selected).toBe(true);
    expect(selected.roles[0].uid).toBe("100000001");
    await request("DELETE", "/v1/account");
    expect((await (await request("GET", "/v1/account")).json()).aid).toBe("10002");
  });

  test("Cookie 与短信验证码登录归一为账号会话", async () => {
    const cookie = await (await request("POST", "/v1/auth/cookie-login", { credential: "stuid=10001; stoken=fixture; mid=fixture-mid" })).json();
    expect(cookie.account.credential_ref).toBe("keychain:account:10001");
    const captcha = await (await request("POST", "/v1/auth/mobile-captcha", { mobile: "13800138000" })).json();
    expect(captcha.action_type).toBe("fixture-action");
    const verified = await (await request("POST", "/v1/auth/mobile-captcha/verification", {
      mobile: "13800138000", session_id: "fixture-session", challenge: "challenge", validate: "validate",
    })).json();
    expect(verified.aigis).toBe("fixture-aigis");
    const sms = await (await request("POST", "/v1/auth/mobile-login", { mobile: "13800138000", captcha: "123456", action_type: captcha.action_type })).json();
    expect(sms.identity.credential).toContain("stoken=fixture");
    expect(sms.roles[0].uid).toBe("100000001");
  });

  test("游戏启动校验安装目录", async () => {
    const response = await request("POST", "/v1/game/launch", { install_path: "/tmp/mhg-missing-game" });
    expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ code: "game_not_installed" });
  });

  test("未登录账号返回 null", async () => expect(await (await request("GET", "/v1/account")).json()).toBeNull());
  test("未知任务返回 404", async () => expect((await request("GET", "/v1/wishes/tasks/missing")).status).toBe(404));
  test("删除账号返回 204", async () => expect((await request("DELETE", "/v1/account")).status).toBe(204));
  test("同步旧端点已删除", async () => expect((await request("POST", "/v1/wishes/sync", { credential: "x" })).status).toBe(404));
  test("图片端点需要鉴权", async () => expect((await request("GET", "/v1/images/gacha/0000000000000000000000000000000000000000.png", undefined, "bad")).status).toBe(401));

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
	    const response = await request("GET", "/v1/game/space-check?install_path=/tmp");
	    const info = await response.json();
	    expect(info).toHaveProperty("available");
	    expect(info).toHaveProperty("required");
	    expect(info).toHaveProperty("sufficient");
	  });

	  test("增值服务接口支持离线 fixture 数据", async () => {
	    const identity = { aid: "10001", mid: "fixture-mid", nickname: "旅行者", credential: "stoken=fixture; mid=fixture-mid" };
	    await request("POST", "/v1/auth/complete", { identity, credential_ref: "keychain:account:10001" });
	    const body = { credential: identity.credential };
	    const characters = await (await request("POST", "/v1/characters/refresh", body)).json();
	    expect(characters[0].name).toBe("芙宁娜");
	    const events = await (await request("POST", "/v1/gacha-events/refresh", body)).json();
	    expect(events[0].orange_up.length).toBeGreaterThan(0);
	    const cycles = await (await request("POST", "/v1/cycles/abyss/refresh", body)).json();
	    expect(cycles[0].kind).toBe("abyss");
	  });

	  test("成就档案支持保存与导出 UIAF", async () => {
	    const archive = await (await request("POST", "/v1/achievements/archives", { name: "主档案" })).json();
	    await request("POST", "/v1/achievements", { archive_id: archive.id, items: [{ achievement_id: 84501, current: 1, status: 2, timestamp: 1_756_000_000 }] });
	    const items = await (await request("GET", `/v1/achievements?archive_id=${archive.id}`)).json();
	    expect(items[0].achievement_id).toBe(84501);
	    const exported = await (await request("GET", `/v1/achievements/export?archive_id=${archive.id}`)).json();
	    expect(exported.list[0].id).toBe(84501);
	  });

	  test("云同步和通知设置提供本地代理", async () => {
	    const login = await (await request("POST", "/v1/cloud/login", { gacha_url: "https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog?authkey=fixture&uid=100000001" })).json();
	    expect(login.uid).toBe("100000001");
	    const upload = await (await request("POST", "/v1/cloud/wishes/upload", { uid: login.uid, token: login.token })).json();
	    expect(upload.uploaded).toBeGreaterThanOrEqual(0);
	    const settings = await (await request("PUT", "/v1/notifications/settings", { daily_commission_enabled: true, daily_commission_time: "00:00" })).json();
	    expect(settings.daily_commission_enabled).toBe(true);
	  });
	});

async function waitForTask(id: string): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const task = await (await request("GET", `/v1/wishes/tasks/${id}`)).json();
    if (task.status === "completed") return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("等待祈愿任务完成超时");
}
