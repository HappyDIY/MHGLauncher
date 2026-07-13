import { afterAll, beforeAll, expect, test } from "vitest";
import { pool, ready, transaction } from "../src/db";
import { issue, requireSession, reverify, revoke } from "../src/auth";
import { dispatch } from "../src/router";

beforeAll(async () => {
  await ready();
  await pool().query("TRUNCATE gacha_records,sessions,users CASCADE");
});

afterAll(async () => { await pool().end(); });

test("迁移账本按顺序完成且可重入", async () => {
  await ready();
  const versions = await pool().query("SELECT version FROM schema_migrations ORDER BY version");
  expect(versions.rows.map(({ version }) => Number(version))).toEqual([1, 2, 3]);
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
  const item = { id: "1", uid: "100000008", gacha_type: "301", uigf_gacha_type: "301", item_id: "1",
    name: "角色", item_type: "角色", rank: 5, time: "2026-01-01T00:00:00Z" };
  const uploaded = await cloudRequest("POST", "/api/v1/gacha/upload", session.token, { uid: "100000009", items: [item] });
  expect(uploaded.status).toBe(200);
  const retrieved = await (await cloudRequest("POST", "/api/v1/gacha/retrieve", session.token, { uid: "100000009" })).json();
  expect(retrieved.items).toHaveLength(1); expect(retrieved.items[0].uid).toBe("100000008");
  expect((await cloudRequest("DELETE", "/api/v1/gacha/100000009", session.token)).status).toBe(404);
});

function cloudRequest(method: string, path: string, token: string, body?: unknown): Promise<Response> {
  return dispatch(new Request(`http://cloud${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
}
