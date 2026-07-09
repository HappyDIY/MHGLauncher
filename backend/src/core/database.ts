import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

const schema = `
PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY);
CREATE TABLE IF NOT EXISTS account(selected INTEGER NOT NULL DEFAULT 0,aid TEXT PRIMARY KEY,mid TEXT NOT NULL,nickname TEXT NOT NULL,credential_ref TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS roles(uid TEXT PRIMARY KEY,account_aid TEXT NOT NULL,nickname TEXT NOT NULL,region TEXT NOT NULL,level INTEGER NOT NULL,selected INTEGER NOT NULL DEFAULT 0,FOREIGN KEY(account_aid) REFERENCES account(aid) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS game_state(id INTEGER PRIMARY KEY CHECK(id=1),install_path TEXT NOT NULL,version TEXT NOT NULL,status TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS wishes(id TEXT PRIMARY KEY,uid TEXT NOT NULL,gacha_type TEXT NOT NULL,uigf_gacha_type TEXT NOT NULL DEFAULT '',item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,rank INTEGER NOT NULL,time TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS wishes_uid_type ON wishes(uid,gacha_type,time DESC);
CREATE TABLE IF NOT EXISTS notes(uid TEXT PRIMARY KEY,payload TEXT NOT NULL,refreshed_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS characters(uid TEXT NOT NULL,avatar_id TEXT NOT NULL,name TEXT NOT NULL,element TEXT NOT NULL,level INTEGER NOT NULL,rarity INTEGER NOT NULL,constellation INTEGER NOT NULL,fetter INTEGER NOT NULL,weapon_name TEXT NOT NULL,weapon_level INTEGER NOT NULL,icon_url TEXT,payload TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(uid,avatar_id));
INSERT OR IGNORE INTO schema_migrations(version) VALUES(1);`;

export type Row = Record<string, unknown>;

export class Store {
  readonly db: Database.Database;

  constructor(path: string) {
    mkdirSync(dirname(path), { recursive: true });
    this.db = new Database(path);
    this.db.exec(schema);
    this.migrateAccounts();
    const columns = this.db.prepare("PRAGMA table_info(wishes)").all() as { name: string }[];
    if (!columns.some(({ name }) => name === "uigf_gacha_type")) {
      this.db.exec("ALTER TABLE wishes ADD COLUMN uigf_gacha_type TEXT NOT NULL DEFAULT ''");
    }
  }

  one(sql: string, ...values: unknown[]): Row | undefined {
    return this.db.prepare(sql).get(...values) as Row | undefined;
  }

  all(sql: string, ...values: unknown[]): Row[] {
    return this.db.prepare(sql).all(...values) as Row[];
  }

  close(): void { this.db.close(); }

  private migrateAccounts(): void {
    const accountColumns = this.db.prepare("PRAGMA table_info(account)").all() as { name: string }[];
    if (accountColumns.some(({ name }) => name === "id")) {
      this.db.exec(`
        ALTER TABLE account RENAME TO account_legacy;
        CREATE TABLE account(selected INTEGER NOT NULL DEFAULT 0,aid TEXT PRIMARY KEY,mid TEXT NOT NULL,nickname TEXT NOT NULL,credential_ref TEXT NOT NULL,updated_at TEXT NOT NULL);
        INSERT INTO account(selected,aid,mid,nickname,credential_ref,updated_at)
          SELECT 1,aid,mid,nickname,credential_ref,updated_at FROM account_legacy;
        DROP TABLE account_legacy;`);
    }
    const roleColumns = this.db.prepare("PRAGMA table_info(roles)").all() as { name: string }[];
    if (!roleColumns.some(({ name }) => name === "account_aid")) {
      const aid = (this.one("SELECT aid FROM account WHERE selected=1 ORDER BY updated_at DESC LIMIT 1")?.aid as string | undefined) ?? "";
      this.db.exec(`
        ALTER TABLE roles RENAME TO roles_legacy;
        CREATE TABLE roles(uid TEXT PRIMARY KEY,account_aid TEXT NOT NULL,nickname TEXT NOT NULL,region TEXT NOT NULL,level INTEGER NOT NULL,selected INTEGER NOT NULL DEFAULT 0,FOREIGN KEY(account_aid) REFERENCES account(aid) ON DELETE CASCADE);`);
      if (aid) {
        const insert = this.db.prepare("INSERT INTO roles(uid,account_aid,nickname,region,level,selected) SELECT uid,?,nickname,region,level,selected FROM roles_legacy");
        insert.run(aid);
      }
      this.db.exec("DROP TABLE roles_legacy");
    }
  }
}
