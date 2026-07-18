import type { Pool, PoolClient } from "pg";

interface Migration { version: number; statements: string[] }

const migrations: Migration[] = [
  { version: 1, statements: [
    "CREATE TABLE IF NOT EXISTS users(uid TEXT PRIMARY KEY,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),updated_at TIMESTAMPTZ NOT NULL DEFAULT now())",
    "CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,reverified_at TIMESTAMPTZ NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now())",
    "CREATE TABLE IF NOT EXISTS gacha_records(uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,id TEXT NOT NULL,gacha_type TEXT NOT NULL,uigf_gacha_type TEXT NOT NULL,item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,rank INTEGER NOT NULL,time TIMESTAMPTZ NOT NULL,payload JSONB NOT NULL,PRIMARY KEY(uid,id))",
  ] },
  { version: 2, statements: ["DROP TABLE IF EXISTS cycle_records"] },
  { version: 3, statements: [
    "ALTER TABLE sessions ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 days')",
    "ALTER TABLE sessions ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()",
    "ALTER TABLE sessions ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ",
    "CREATE INDEX IF NOT EXISTS sessions_uid_active ON sessions(uid) WHERE revoked_at IS NULL",
  ] },
  { version: 4, statements: [
    "CREATE TABLE IF NOT EXISTS achievement_archives(uid TEXT PRIMARY KEY REFERENCES users(uid) ON DELETE CASCADE,payload JSONB NOT NULL,updated_at TIMESTAMPTZ NOT NULL DEFAULT now())",
  ] },
  { version: 5, statements: [
    "CREATE TABLE IF NOT EXISTS app_releases(id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,version TEXT NOT NULL UNIQUE,download_url TEXT NOT NULL,sha256 TEXT NOT NULL,size BIGINT NOT NULL,changelog TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','archived')),created_at TIMESTAMPTZ NOT NULL DEFAULT now(),published_at TIMESTAMPTZ)",
    "CREATE UNIQUE INDEX IF NOT EXISTS app_releases_one_published ON app_releases(status) WHERE status='published'",
    "CREATE TABLE IF NOT EXISTS admin_audit_events(id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,request_id TEXT NOT NULL UNIQUE,actor TEXT NOT NULL,action TEXT NOT NULL,target_type TEXT NOT NULL,target_ref TEXT NOT NULL,result TEXT NOT NULL CHECK(result IN ('success','failure')),metadata JSONB NOT NULL DEFAULT '{}'::jsonb,created_at TIMESTAMPTZ NOT NULL DEFAULT now())",
    "CREATE INDEX IF NOT EXISTS admin_audit_events_created ON admin_audit_events(created_at DESC,id DESC)",
  ] },
];

export async function migrate(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query("SELECT pg_advisory_lock(781942601)");
    await client.query("CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY,applied_at TIMESTAMPTZ NOT NULL DEFAULT now())");
    const result = await client.query<{ version: number }>("SELECT version FROM schema_migrations ORDER BY version");
    const applied = new Set(result.rows.map(({ version }) => version));
    for (const migration of migrations) {
      if (applied.has(migration.version)) continue;
      await client.query("BEGIN");
      try {
        for (const statement of migration.statements) await client.query(statement);
        await client.query("INSERT INTO schema_migrations(version) VALUES($1)", [migration.version]);
        await verify(client, migration.version);
        await client.query("COMMIT");
      } catch (error) { await client.query("ROLLBACK"); throw error; }
    }
    const latest = Number((await client.query("SELECT COALESCE(MAX(version),0) version FROM schema_migrations")).rows[0]?.version ?? 0);
    if (latest !== migrations.at(-1)?.version) throw new Error("cloud schema version mismatch");
  } finally {
    await client.query("SELECT pg_advisory_unlock(781942601)").catch(() => undefined);
    client.release();
  }
}

async function verify(client: PoolClient, version: number): Promise<void> {
  if (version < 3) return;
  const result = await client.query<{ column_name: string }>(`SELECT column_name FROM information_schema.columns
    WHERE table_schema='public' AND table_name='sessions'`);
  const columns = new Set(result.rows.map(({ column_name }) => column_name));
  for (const required of ["expires_at", "last_seen_at", "revoked_at"]) {
    if (!columns.has(required)) throw new Error(`cloud sessions missing ${required}`);
  }
  if (version >= 4) {
    const archive = await client.query("SELECT to_regclass('public.achievement_archives') name");
    if (!archive.rows[0]?.name) throw new Error("cloud achievement archive table missing");
  }
  if (version >= 5) {
    for (const table of ["app_releases", "admin_audit_events"]) {
      const result = await client.query("SELECT to_regclass($1) name", [`public.${table}`]);
      if (!result.rows[0]?.name) throw new Error(`cloud ${table} table missing`);
    }
  }
}
