import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

const schema = `
PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY);
CREATE TABLE IF NOT EXISTS account(id INTEGER PRIMARY KEY CHECK(id=1),aid TEXT NOT NULL,mid TEXT NOT NULL,nickname TEXT NOT NULL,credential_ref TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS roles(uid TEXT PRIMARY KEY,nickname TEXT NOT NULL,region TEXT NOT NULL,level INTEGER NOT NULL,selected INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS game_state(id INTEGER PRIMARY KEY CHECK(id=1),install_path TEXT NOT NULL,version TEXT NOT NULL,status TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS wishes(id TEXT PRIMARY KEY,uid TEXT NOT NULL,gacha_type TEXT NOT NULL,uigf_gacha_type TEXT NOT NULL DEFAULT '',item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,rank INTEGER NOT NULL,time TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS wishes_uid_type ON wishes(uid,gacha_type,time DESC);
CREATE TABLE IF NOT EXISTS notes(uid TEXT PRIMARY KEY,payload TEXT NOT NULL,refreshed_at TEXT NOT NULL);
INSERT OR IGNORE INTO schema_migrations(version) VALUES(1);`;

export type Row = Record<string, unknown>;

export class Store {
  readonly db: Database.Database;

  constructor(path: string) {
    mkdirSync(dirname(path), { recursive: true });
    this.db = new Database(path);
    this.db.exec(schema);
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
}
