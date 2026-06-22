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

  test("游戏启动保持 501", async () => {
    const response = await request("POST", "/v1/game/launch", {});
    expect(response.status).toBe(501); expect(await response.json()).toMatchObject({ code: "launch_not_implemented" });
  });

  test("未登录账号返回 null", async () => expect(await (await request("GET", "/v1/account")).json()).toBeNull());
  test("未知任务返回 404", async () => expect((await request("GET", "/v1/wishes/tasks/missing")).status).toBe(404));
  test("删除账号返回 204", async () => expect((await request("DELETE", "/v1/account")).status).toBe(204));
  test("同步旧端点已删除", async () => expect((await request("POST", "/v1/wishes/sync", { credential: "x" })).status).toBe(404));
  test("图片端点需要鉴权", async () => expect((await request("GET", "/v1/images/gacha/0000000000000000000000000000000000000000.png", undefined, "bad")).status).toBe(401));
});
