import { afterAll, beforeAll, expect, test } from "vitest";
import { pool, ready, transaction } from "../src/db";
import { issue, requireSession, reverify, revoke } from "../src/auth";
import { dispatch } from "../src/router";
import { dispatchAdmin } from "../src/admin-router";

beforeAll(async () => {
  await ready();
  await pool().query("TRUNCATE admin_audit_events,app_releases,achievement_archives,gacha_records,sessions,users CASCADE");
});

afterAll(async () => { await pool().end(); });

test("迁移账本按顺序完成且可重入", async () => {
  await ready();
  const versions = await pool().query("SELECT version FROM schema_migrations ORDER BY version");
  expect(versions.rows.map(({ version }) => Number(version))).toEqual([1, 2, 3, 4, 5]);
  const columns = await pool().query("SELECT column_name FROM information_schema.columns WHERE table_name='sessions'");
  expect(columns.rows.map(({ column_name }) => column_name)).toEqual(expect.arrayContaining([
    "expires_at", "last_seen_at", "revoked_at",
  ]));
});

test("事务失败完整回滚", async () => {
  await expect(transaction(async (client) => {
    await client.query("INSERT INTO users(uid) VALUES('100000001')");
    throw new Error("fault");
  })).rejects.toThrow("fault");
  expect((await pool().query("SELECT uid FROM users WHERE uid='100000001'")).rowCount).toBe(0);
});

test("初始记录失败时用户与会话一并回滚", async () => {
  await expect(issue("100000002", async (client) => {
    await client.query("INSERT INTO users(uid) VALUES('100000003')");
    throw new Error("initialize fault");
  })).rejects.toThrow("initialize fault");
  expect((await pool().query("SELECT uid FROM users WHERE uid IN ('100000002','100000003')")).rowCount).toBe(0);
});

test("会话轮换、撤销和 UID 绑定", async () => {
  const first = await issue("100000004");
  await expect(reverify(first.token, "100000005")).rejects.toMatchObject({ code: "identity_mismatch" });
  const rotated = await reverify(first.token, "100000004");
  await expect(requireSession(first.token)).rejects.toMatchObject({ code: "unauthorized" });
  expect((await requireSession(rotated.token)).uid).toBe("100000004");
  await revoke(rotated.token);
  await expect(requireSession(rotated.token)).rejects.toMatchObject({ code: "unauthorized" });
});

test("会话同时执行绝对和空闲期限", async () => {
  const idle = await issue("100000006");
  await pool().query("UPDATE sessions SET last_seen_at=now()-interval '8 days' WHERE uid='100000006'");
  await expect(requireSession(idle.token)).rejects.toMatchObject({ code: "unauthorized" });
  const expired = await issue("100000007");
  await pool().query("UPDATE sessions SET expires_at=now()-interval '1 second' WHERE uid='100000007'");
  await expect(requireSession(expired.token)).rejects.toMatchObject({ code: "unauthorized" });
});

test("数据接口仅使用 bearer 会话 UID", async () => {
  const session = await issue("100000008");
	  const item = { id: "1", uid: "100000008", gacha_type: "301", uigf_gacha_type: "301", item_id: "",
    name: "角色", item_type: "角色", rank: 5, time: "2026-01-01T00:00:00Z" };
  const uploaded = await cloudRequest("POST", "/api/v1/gacha/upload", session.token, { items: [item] });
  expect(uploaded.status).toBe(200);
  const retrieved = await (await cloudRequest("POST", "/api/v1/gacha/retrieve", session.token, { uid: "100000009" })).json();
  expect(retrieved.items).toHaveLength(1); expect(retrieved.items[0].uid).toBe("100000008");
  expect((await cloudRequest("DELETE", "/api/v1/gacha/100000009", session.token)).status).toBe(404);
});

test("成就档案按会话 UID 覆盖上传并取回", async () => {
  const session = await issue("100000012");
  const item = { achievement_id: 84501, current: 1, status: 3, timestamp: 1_756_000_000 };
  const uploaded = await cloudRequest("POST", "/api/v1/achievements/upload", session.token, { items: [item, item] });
  expect(await uploaded.json()).toEqual({ uploaded: 1 });
  const retrieved = await cloudRequest("POST", "/api/v1/achievements/retrieve", session.token, {});
  expect(await retrieved.json()).toEqual({ items: [item] });
});

test("上传严格校验记录、数组和请求体边界", async () => {
  const session = await issue("100000010");
  const item = { id: "1", uid: "100000010", gacha_type: "301", uigf_gacha_type: "301", item_id: "1",
    name: "角色", item_type: "角色", rank: 5, time: "2026-01-01T00:00:00Z" };
  expect((await cloudRequest("POST", "/api/v1/gacha/upload", session.token, { items: [{ ...item, rank: 9 }] })).status).toBe(422);
  const mismatched = await cloudRequest("POST", "/api/v1/gacha/upload", session.token, {
    items: [{ ...item, uid: "100000011" }],
  });
  expect(mismatched.status).toBe(403);
  expect(await mismatched.json()).toMatchObject({ code: "identity_mismatch" });
  expect((await cloudRequest("POST", "/api/v1/gacha/upload", session.token, { items: [item], ignored: true })).status).toBe(422);
  const tooLarge = await dispatch(new Request("http://cloud/api/v1/gacha/upload", {
    method: "POST", headers: { Authorization: `Bearer ${session.token}`, "Content-Type": "application/json", "Content-Length": String(16 * 1024 * 1024 + 1) }, body: "{}",
  }));
  expect(tooLarge.status).toBe(413); expect(await tooLarge.json()).toMatchObject({ code: "request_too_large" });
  const malformed = await dispatch(new Request("http://cloud/api/v1/gacha/upload", {
    method: "POST", headers: { Authorization: `Bearer ${session.token}`, "Content-Type": "application/json" }, body: "{",
  }));
  expect(malformed.status).toBe(400); expect(await malformed.json()).toMatchObject({ code: "invalid_json" });
});

test("读取历史坏 payload 返回稳定错误而不强制转换", async () => {
  const session = await issue("100000011");
  await pool().query(`INSERT INTO gacha_records(uid,id,gacha_type,uigf_gacha_type,item_id,name,item_type,rank,time,payload)
    VALUES($1,'1','301','301','1','角色','角色',5,now(),$2)`, ["100000011", { uid: "100000011", id: "broken" }]);
  const response = await cloudRequest("POST", "/api/v1/gacha/retrieve", session.token, {});
  expect(response.status).toBe(500); expect(await response.json()).toEqual({ code: "stored_data_invalid", message: "云端记录格式无效" });
});

test("管理接口认证、用户聚合、会话撤销与删除保持审计一致", async () => {
  process.env.MHG_ADMIN_SERVICE_TOKEN = "test-service-token";
  process.env.MHG_ADMIN_AUDIT_KEY = "test-audit-key";
  const session = await issue("100000020");
  const headers = adminHeaders("request_users_1");
  expect((await dispatchAdmin(new Request("http://cloud/api/admin/v1/overview"))).status).toBe(401);
  const users = await dispatchAdmin(new Request("http://cloud/api/admin/v1/users?query=100000020", { headers }));
  expect((await users.json()).items[0]).toMatchObject({ uid: "100000020", active_sessions: 1 });
  const revoked = await dispatchAdmin(new Request("http://cloud/api/admin/v1/users/100000020/revoke-sessions", { method: "POST", headers: adminHeaders("request_revoke_1") }));
  expect(await revoked.json()).toEqual({ revoked: 1 });
  await expect(requireSession(session.token)).rejects.toMatchObject({ code: "unauthorized" });
  const removed = await dispatchAdmin(new Request("http://cloud/api/admin/v1/users/100000020", { method: "DELETE", headers: adminHeaders("request_delete_1") }));
  expect(await removed.json()).toMatchObject({ deleted: true, sessions: 1 });
  const event = await pool().query("SELECT target_ref FROM admin_audit_events WHERE action='user.delete'");
  expect(event.rows[0].target_ref).toMatch(/^uid_hmac:/); expect(event.rows[0].target_ref).not.toContain("100000020");
});

test("版本草稿、发布和回滚保持唯一当前版本", async () => {
  process.env.MHG_ADMIN_SERVICE_TOKEN = "test-service-token";
  const first = await createAdminRelease("1.0.0", "request_release_1");
  const second = await createAdminRelease("1.1.0", "request_release_2");
  expect(first.status).toBe("draft");
  await dispatchAdmin(new Request(`http://cloud/api/admin/v1/releases/${first.id}/publish`, { method: "POST", headers: adminHeaders("request_publish_1") }));
  await dispatchAdmin(new Request(`http://cloud/api/admin/v1/releases/${second.id}/publish`, { method: "POST", headers: adminHeaders("request_publish_2") }));
  expect(Number((await pool().query("SELECT COUNT(*) count FROM app_releases WHERE status='published'")).rows[0].count)).toBe(1);
  const latest = await dispatch(new Request("http://cloud/api/v1/updates/latest"));
  expect(await latest.json()).toMatchObject({ version: "1.1.0", sha256: "a".repeat(64) });
  await dispatchAdmin(new Request(`http://cloud/api/admin/v1/releases/${first.id}/rollback`, { method: "POST", headers: adminHeaders("request_rollback_1") }));
  expect((await pool().query("SELECT version FROM app_releases WHERE status='published'")).rows[0].version).toBe("1.0.0");
});

function cloudRequest(method: string, path: string, token: string, body?: unknown): Promise<Response> {
  return dispatch(new Request(`http://cloud${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
}

function adminHeaders(requestId: string): HeadersInit {
  return { Authorization: "Bearer test-service-token", "X-MHG-Admin-Actor": "owner@example.com", "X-Request-ID": requestId, "Content-Type": "application/json" };
}

async function createAdminRelease(version: string, requestId: string): Promise<any> {
  const response = await dispatchAdmin(new Request("http://cloud/api/admin/v1/releases", { method: "POST", headers: adminHeaders(requestId), body: JSON.stringify({
    version, download_url: `https://download.example/MHGLauncher-${version}.dmg`, sha256: "a".repeat(64), size: 1024, changelog: "测试版本",
  }) }));
  expect(response.status).toBe(201); return response.json();
}
