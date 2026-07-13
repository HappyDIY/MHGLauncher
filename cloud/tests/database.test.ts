import { afterAll, beforeAll, expect, test } from "vitest";
import { pool, ready, transaction } from "../src/db";

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
