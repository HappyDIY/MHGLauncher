import Database from "better-sqlite3";
import { acquirePrivateUmask } from "./private-umask";
import { chmodSync, existsSync, lstatSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { securityMigrations } from "./database-security-migrations";

const schema = `
	PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
		CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY);
	CREATE TABLE IF NOT EXISTS account(selected INTEGER NOT NULL DEFAULT 0,aid TEXT PRIMARY KEY,mid TEXT NOT NULL,nickname TEXT NOT NULL,credential_ref TEXT NOT NULL,updated_at TEXT NOT NULL);
	CREATE TABLE IF NOT EXISTS roles(uid TEXT PRIMARY KEY,account_aid TEXT NOT NULL,nickname TEXT NOT NULL,region TEXT NOT NULL,level INTEGER NOT NULL,selected INTEGER NOT NULL DEFAULT 0,FOREIGN KEY(account_aid) REFERENCES account(aid) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS game_state(id INTEGER PRIMARY KEY CHECK(id=1),install_path TEXT NOT NULL,version TEXT NOT NULL,status TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS wishes(id TEXT PRIMARY KEY,uid TEXT NOT NULL,gacha_type TEXT NOT NULL,uigf_gacha_type TEXT NOT NULL DEFAULT '',item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,rank INTEGER NOT NULL,time TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS wishes_uid_type ON wishes(uid,gacha_type,time DESC);
	CREATE TABLE IF NOT EXISTS notes(uid TEXT PRIMARY KEY,payload TEXT NOT NULL,refreshed_at TEXT NOT NULL);
	INSERT OR IGNORE INTO schema_migrations(version) VALUES(1);`;

const migrations: [number, string][] = [[2, `
CREATE TABLE IF NOT EXISTS characters(uid TEXT NOT NULL,avatar_id TEXT NOT NULL,name TEXT NOT NULL,element TEXT NOT NULL,level INTEGER NOT NULL,rarity INTEGER NOT NULL,constellation INTEGER NOT NULL,fetter INTEGER NOT NULL,weapon_name TEXT NOT NULL,weapon_level INTEGER NOT NULL,icon_url TEXT,payload TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(uid,avatar_id));
CREATE TABLE IF NOT EXISTS achievement_archives(id TEXT PRIMARY KEY,name TEXT NOT NULL,selected INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS achievements(archive_id TEXT NOT NULL,achievement_id INTEGER NOT NULL,current INTEGER NOT NULL,status INTEGER NOT NULL,timestamp INTEGER NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(archive_id,achievement_id),FOREIGN KEY(archive_id) REFERENCES achievement_archives(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS gacha_events(id TEXT PRIMARY KEY,version TEXT NOT NULL,gacha_type TEXT NOT NULL,name TEXT NOT NULL,started_at TEXT NOT NULL,ended_at TEXT NOT NULL,orange_up TEXT NOT NULL,purple_up TEXT NOT NULL,banner_url TEXT,updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS notification_settings(id INTEGER PRIMARY KEY CHECK(id=1),daily_commission_enabled INTEGER NOT NULL,daily_commission_time TEXT NOT NULL,resin_full_enabled INTEGER NOT NULL,gacha_refresh_enabled INTEGER NOT NULL,version_update_enabled INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS notification_state(key TEXT PRIMARY KEY,last_triggered_at TEXT NOT NULL,state TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS cloud_sessions(uid TEXT PRIMARY KEY,token_ref TEXT NOT NULL,reverified_at TEXT NOT NULL,updated_at TEXT NOT NULL);
INSERT OR IGNORE INTO notification_settings(id,daily_commission_enabled,daily_commission_time,resin_full_enabled,gacha_refresh_enabled,version_update_enabled) VALUES(1,0,'20:00',0,1,1);`], [3, `
CREATE INDEX IF NOT EXISTS wishes_uid_time_id ON wishes(uid,time DESC,id DESC);
CREATE INDEX IF NOT EXISTS wishes_uid_type_time_id ON wishes(uid,gacha_type,time DESC,id DESC);
CREATE INDEX IF NOT EXISTS wishes_uid_uigf_time_id ON wishes(uid,uigf_gacha_type,time DESC,id DESC);`], [4, `
DROP TABLE IF EXISTS cycle_records;
DELETE FROM notification_state WHERE key LIKE 'cycle:abyss:%' OR key LIKE 'cycle:theatre:%' OR key LIKE 'cycle:hard:%';
ALTER TABLE notification_settings RENAME TO notification_settings_legacy;
CREATE TABLE notification_settings(id INTEGER PRIMARY KEY CHECK(id=1),daily_commission_enabled INTEGER NOT NULL,daily_commission_time TEXT NOT NULL,resin_full_enabled INTEGER NOT NULL,gacha_refresh_enabled INTEGER NOT NULL,version_update_enabled INTEGER NOT NULL);
INSERT INTO notification_settings(id,daily_commission_enabled,daily_commission_time,resin_full_enabled,gacha_refresh_enabled,version_update_enabled)
  SELECT id,daily_commission_enabled,daily_commission_time,resin_full_enabled,gacha_refresh_enabled,version_update_enabled FROM notification_settings_legacy;
DROP TABLE notification_settings_legacy;`]];

export type Row = Record<string, unknown>;

export class Store {
  readonly db: Database.Database;
  private readonly statements = new Map<string, Database.Statement>();

  constructor(path: string) {
    const restoreUmask = acquirePrivateUmask(0o077);
    try {
      const existing = existsSync(path), backup = `${path}.pre-security.bak`;
      mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
      if (existing && !lstatSync(path).isFile()) throw new Error("数据库路径必须是普通文件");
      if (existsSync(backup) && !lstatSync(backup).isFile()) {
        throw new Error("数据库备份路径必须是普通文件");
      }
      this.db = new Database(path);
      chmodSync(path, 0o600);
      if (existing && !existsSync(backup)) {
        this.db.pragma("wal_checkpoint(FULL)");
        this.db.exec(`VACUUM INTO '${backup.replaceAll("'", "''")}'`);
      }
      if (existsSync(backup)) chmodSync(backup, 0o600);
      this.db.exec(schema);
      this.runMigrations();
      const columns = this.db.prepare("PRAGMA table_info(wishes)").all() as { name: string }[];
      if (!columns.some(({ name }) => name === "uigf_gacha_type")) {
        this.db.exec("ALTER TABLE wishes ADD COLUMN uigf_gacha_type TEXT NOT NULL DEFAULT ''");
      }
    } finally {
      restoreUmask();
    }
  }

  one(sql: string, ...values: unknown[]): Row | undefined {
    return this.prepare(sql).get(...values) as Row | undefined;
  }

  all(sql: string, ...values: unknown[]): Row[] {
    return this.prepare(sql).all(...values) as Row[];
  }

  close(): void { this.statements.clear(); this.db.close(); }

  prepare(sql: string): Database.Statement {
    const cached = this.statements.get(sql);
    if (cached) return cached;
    const statement = this.db.prepare(sql);
    this.statements.set(sql, statement);
    return statement;
  }

	  private runMigrations(): void {
	    let current = Number(this.one("SELECT MAX(version) version FROM schema_migrations")?.version ?? 0);
	    for (const [version, sql] of migrations) {
      if (version <= current) continue;
      this.db.transaction(() => {
        this.db.exec(sql);
	        this.db.prepare("INSERT OR IGNORE INTO schema_migrations(version) VALUES(?)").run(version);
	      })();
	      current = version;
	    }
	    for (const [version, migrate] of securityMigrations) {
	      if (version <= current) continue;
	      this.db.transaction(() => {
	        migrate(this.db);
	        this.db.prepare("INSERT INTO schema_migrations(version) VALUES(?)").run(version);
	      })();
	      current = version;
	    }
	  }
	}
