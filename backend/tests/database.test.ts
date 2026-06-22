import { existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { expect, test } from "vitest";
import Database from "better-sqlite3";
import { fixture } from "./helpers";

test("复用旧 SQLite 数据并建立迁移记录", () => {
  const app = fixture();
  app.store.db.prepare("INSERT INTO account VALUES(1,'a','m','n','keychain:x','2026-01-01T00:00:00Z')").run();
  expect(app.accounts.get()?.aid).toBe("a");
  expect(app.store.one("SELECT version FROM schema_migrations")?.version).toBe(1);
});

test("数据库启用 WAL", () => expect(fixture().store.one("PRAGMA journal_mode")?.journal_mode).toBe("wal"));
test("数据目录自动建立", () => { const app = fixture(); const marker = join(app.settings.dataDir, "marker"); writeFileSync(marker, "x"); expect(existsSync(marker)).toBe(true); });
test("SQLite 驱动可读取原表", () => { const app = fixture(); expect(new Database(app.settings.databasePath, { readonly: true }).prepare("SELECT name FROM sqlite_master WHERE name='wishes'").get()).toBeTruthy(); });
