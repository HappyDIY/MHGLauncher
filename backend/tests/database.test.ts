import { existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { expect, test } from "vitest";
import Database from "better-sqlite3";
import { fixture } from "./helpers";
import { Store } from "../src/core/database";

test("复用旧 SQLite 数据并建立迁移记录", () => {
  const app = fixture();
  app.store.db.prepare("INSERT INTO account VALUES(1,'a','m','n','keychain:x','2026-01-01T00:00:00Z')").run();
  expect(app.accounts.get()?.aid).toBe("a");
  expect(app.store.one("SELECT MAX(version) version FROM schema_migrations")?.version).toBe(8);
});

test("数据库启用 WAL", () => expect(fixture().store.one("PRAGMA journal_mode")?.journal_mode).toBe("wal"));
test("数据目录自动建立", () => { const app = fixture(); const marker = join(app.settings.dataDir, "marker"); writeFileSync(marker, "x"); expect(existsSync(marker)).toBe(true); });
test("SQLite 驱动可读取原表", () => { const app = fixture(); expect(new Database(app.settings.databasePath, { readonly: true }).prepare("SELECT name FROM sqlite_master WHERE name='wishes'").get()).toBeTruthy(); });

test("安全迁移保留跨 UID 同号祈愿并隔离坏时间", () => {
  const root = mkdtempSync(join(tmpdir(), "mhg-migration-")), path = join(root, "legacy.db");
  const legacy = new Database(path);
  legacy.exec(`CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY);
    INSERT INTO schema_migrations VALUES(4);
    CREATE TABLE account(selected INTEGER,aid TEXT PRIMARY KEY,mid TEXT,nickname TEXT,credential_ref TEXT,updated_at TEXT);
    CREATE TABLE roles(uid TEXT PRIMARY KEY,account_aid TEXT,nickname TEXT,region TEXT,level INTEGER,selected INTEGER);
    CREATE TABLE wishes(id TEXT PRIMARY KEY,uid TEXT,gacha_type TEXT,uigf_gacha_type TEXT,item_id TEXT,name TEXT,item_type TEXT,rank INTEGER,time TEXT);
    CREATE TABLE achievement_archives(id TEXT PRIMARY KEY,name TEXT,selected INTEGER,created_at TEXT,updated_at TEXT);
    CREATE TABLE achievements(archive_id TEXT,achievement_id INTEGER,current INTEGER,status INTEGER,timestamp INTEGER,updated_at TEXT);
    INSERT INTO wishes VALUES('1','100000001','301','301','','A','角色',5,'2026-01-01 08:00:00');
    INSERT INTO wishes VALUES('2','100000002','301','301','','B','角色',5,'invalid');`);
  legacy.close();
  const store = new Store(path);
  expect(store.all("SELECT uid,id,time,time_epoch FROM wishes")).toHaveLength(1);
  expect(store.all("SELECT * FROM wishes_quarantine")).toHaveLength(1);
  expect(store.one("SELECT MAX(version) version FROM schema_migrations")?.version).toBe(8);
  store.close();
  expect(existsSync(`${path}.pre-security.bak`)).toBe(true);
  const reopened = new Store(path);
  expect(reopened.all("SELECT * FROM wishes")).toHaveLength(1);
  reopened.close();
});
