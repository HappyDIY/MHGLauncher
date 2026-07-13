import type Database from "better-sqlite3";

type Row = Record<string, unknown>;

export const securityMigrations: Array<[number, (db: Database.Database) => void]> = [
  [5, migrateAccountsAndRoles],
  [6, migrateWishes],
  [7, migrateAchievements],
  [8, verifySecuritySchema],
];

function migrateAccountsAndRoles(db: Database.Database): void {
  if (table(db, "account_legacy")) {
    createAccount(db);
    db.exec(`INSERT OR IGNORE INTO account(selected,aid,mid,nickname,credential_ref,updated_at)
      SELECT selected,aid,mid,nickname,credential_ref,updated_at FROM account_legacy`);
    db.exec("DROP TABLE account_legacy");
  } else if (columns(db, "account").includes("id")) {
    db.exec("ALTER TABLE account RENAME TO account_legacy");
    createAccount(db);
    db.exec(`INSERT OR IGNORE INTO account(selected,aid,mid,nickname,credential_ref,updated_at)
      SELECT 1,aid,mid,nickname,credential_ref,updated_at FROM account_legacy`);
    db.exec("DROP TABLE account_legacy");
  }

  if (table(db, "roles_legacy")) {
    createRoles(db);
    copyLegacyRoles(db);
  } else if (!compositePrimaryKey(db, "roles", ["account_aid", "uid"])) {
    db.exec("ALTER TABLE roles RENAME TO roles_legacy");
    createRoles(db);
    copyLegacyRoles(db);
  }
}

function migrateWishes(db: Database.Database): void {
  if (compositePrimaryKey(db, "wishes", ["uid", "id"]) && columns(db, "wishes").includes("time_epoch")) return;
  if (!table(db, "wishes_legacy")) db.exec("ALTER TABLE wishes RENAME TO wishes_legacy");
  createWishes(db);
  const insert = db.prepare(`INSERT INTO wishes(id,uid,gacha_type,uigf_gacha_type,item_id,name,item_type,rank,time,time_epoch)
    VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(uid,id) DO NOTHING`);
  const quarantine = db.prepare("INSERT INTO wishes_quarantine(uid,id,payload,reason) VALUES(?,?,?,?)");
  for (const row of db.prepare("SELECT * FROM wishes_legacy").all() as Row[]) {
    const normalized = normalizeTime(String(row.time ?? ""));
    if (!normalized) {
      quarantine.run(String(row.uid ?? ""), String(row.id ?? ""), JSON.stringify(row), "invalid_time");
      continue;
    }
    insert.run(row.id, row.uid, row.gacha_type, row.uigf_gacha_type ?? "", row.item_id, row.name,
      row.item_type, row.rank, normalized.iso, normalized.epoch);
  }
  db.exec("DROP TABLE wishes_legacy");
}

function migrateAchievements(db: Database.Database): void {
  if (!columns(db, "achievement_archives").includes("revision")) {
    db.exec("ALTER TABLE achievement_archives ADD COLUMN revision INTEGER NOT NULL DEFAULT 0");
  }
}

function verifySecuritySchema(db: Database.Database): void {
  if (!compositePrimaryKey(db, "roles", ["account_aid", "uid"])) throw new Error("roles schema invalid");
  if (!compositePrimaryKey(db, "wishes", ["uid", "id"])) throw new Error("wishes schema invalid");
  if (!columns(db, "wishes").includes("time_epoch")) throw new Error("wishes time schema invalid");
}

function createAccount(db: Database.Database): void {
  db.exec(`CREATE TABLE IF NOT EXISTS account(selected INTEGER NOT NULL DEFAULT 0,aid TEXT PRIMARY KEY,
    mid TEXT NOT NULL,nickname TEXT NOT NULL,credential_ref TEXT NOT NULL,updated_at TEXT NOT NULL)`);
}

function createRoles(db: Database.Database): void {
  db.exec(`CREATE TABLE IF NOT EXISTS roles(uid TEXT NOT NULL,account_aid TEXT NOT NULL,nickname TEXT NOT NULL,
    region TEXT NOT NULL,level INTEGER NOT NULL,selected INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(account_aid,uid),FOREIGN KEY(account_aid) REFERENCES account(aid) ON DELETE CASCADE)`);
}

function copyLegacyRoles(db: Database.Database): void {
  const legacyColumns = columns(db, "roles_legacy");
  if (legacyColumns.includes("account_aid")) {
    db.exec(`INSERT OR IGNORE INTO roles(uid,account_aid,nickname,region,level,selected)
      SELECT uid,account_aid,nickname,region,level,selected FROM roles_legacy`);
  } else {
    const aid = db.prepare("SELECT aid FROM account ORDER BY selected DESC,updated_at DESC LIMIT 1").pluck().get();
    if (aid) db.prepare(`INSERT OR IGNORE INTO roles(uid,account_aid,nickname,region,level,selected)
      SELECT uid,?,nickname,region,level,selected FROM roles_legacy`).run(aid);
  }
  db.exec("DROP TABLE roles_legacy");
}

function createWishes(db: Database.Database): void {
  db.exec(`DROP INDEX IF EXISTS wishes_uid_type;
    DROP INDEX IF EXISTS wishes_uid_time_id;
    DROP INDEX IF EXISTS wishes_uid_type_time_id;
    DROP INDEX IF EXISTS wishes_uid_uigf_time_id;
    CREATE TABLE IF NOT EXISTS wishes(id TEXT NOT NULL,uid TEXT NOT NULL,gacha_type TEXT NOT NULL,
    uigf_gacha_type TEXT NOT NULL DEFAULT '',item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,
    rank INTEGER NOT NULL,time TEXT NOT NULL,time_epoch INTEGER NOT NULL,PRIMARY KEY(uid,id));
    CREATE TABLE IF NOT EXISTS wishes_quarantine(uid TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,reason TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS wishes_uid_time_id ON wishes(uid,time_epoch DESC,LENGTH(id) DESC,id DESC);
    CREATE INDEX IF NOT EXISTS wishes_uid_type_time_id ON wishes(uid,gacha_type,time_epoch DESC,LENGTH(id) DESC,id DESC);
    CREATE INDEX IF NOT EXISTS wishes_uid_uigf_time_id ON wishes(uid,uigf_gacha_type,time_epoch DESC,LENGTH(id) DESC,id DESC)`);
}

function normalizeTime(value: string): { iso: string; epoch: number } | null {
  const explicit = /(Z|[+-]\d{2}:\d{2})$/i.test(value) ? value : `${value.replace(" ", "T")}+08:00`;
  const epoch = Date.parse(explicit);
  return Number.isFinite(epoch) ? { iso: new Date(epoch).toISOString(), epoch } : null;
}

function table(db: Database.Database, name: string): boolean {
  return Boolean(db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(name));
}

function columns(db: Database.Database, name: string): string[] {
  return (db.prepare(`PRAGMA table_info(${name})`).all() as Array<{ name: string }>).map((value) => value.name);
}

function compositePrimaryKey(db: Database.Database, name: string, expected: string[]): boolean {
  const keys = (db.prepare(`PRAGMA table_info(${name})`).all() as Array<{ name: string; pk: number }>)
    .filter(({ pk }) => pk > 0).sort((left, right) => left.pk - right.pk).map(({ name }) => name);
  return keys.join("\0") === expected.join("\0");
}
