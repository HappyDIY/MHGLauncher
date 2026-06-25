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
});
