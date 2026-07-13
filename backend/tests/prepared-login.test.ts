import { describe, expect, test, vi } from "vitest";
import type { AccountIdentity, GameRole } from "../src/core/models";
import { PreparedLoginStore } from "../src/services/prepared-logins";
import { fixture, request } from "./helpers";

const identity: AccountIdentity = { aid: "10001", mid: "mid-1", nickname: "旅行者", credential: "stoken=secret" };
const roles: GameRole[] = [{ uid: "100000001", nickname: "旅行者", region: "cn_gf01", level: 60, selected: true }];

describe("一次性登录事务", () => {
  test("仅最新登录意图可生成事务且事务只能消费一次", () => {
    const store = new PreparedLoginStore(); store.begin("qr:old"); store.begin("qr:new");
    expect(() => store.prepare("qr:old", identity, roles)).toThrow("更新的操作");
    const prepared = store.prepare("qr:new", identity, roles);
    expect(store.consume(prepared.transaction_id).identity.aid).toBe("10001");
    expect(() => store.consume(prepared.transaction_id)).toThrow("无效或已过期");
  });

  test("五分钟后事务失效", () => {
    vi.useFakeTimers(); const store = new PreparedLoginStore(); store.begin("cookie:1");
    const prepared = store.prepare("cookie:1", identity, roles); vi.advanceTimersByTime(300_001);
    expect(() => store.consume(prepared.transaction_id)).toThrow("无效或已过期"); vi.useRealTimers();
  });

  test("角色同步和启动凭据绑定当前账号", async () => {
    fixture();
    const prepared = await (await request("POST", "/v1/auth/cookie-login", { credential: "stuid=10001; stoken=x; mid=mid-1" })).json();
    await request("POST", "/v1/auth/commit", { transaction_id: prepared.transaction_id });
    const mismatch = "stuid=10002; stoken=x; mid=mid-2";
    expect((await request("POST", "/v1/roles/sync", { aid: "10001", credential: mismatch })).status).toBe(403);
    expect((await request("POST", "/v1/game/launch", { install_path: "/tmp/missing", credential: mismatch })).status).toBe(403);
  });
});
