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
];

export async function migrate(pool: Pool): Promise<void> {
  await pool.query("CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY,applied_at TIMESTAMPTZ NOT NULL DEFAULT now())");
  const result = await pool.query<{ version: number }>("SELECT version FROM schema_migrations ORDER BY version");
  const applied = new Set(result.rows.map(({ version }) => version));
  for (const migration of migrations) {
    if (applied.has(migration.version)) continue;
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      for (const statement of migration.statements) await client.query(statement);
      await client.query("INSERT INTO schema_migrations(version) VALUES($1)", [migration.version]);
      await verify(client, migration.version);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
  const latest = Number((await pool.query("SELECT COALESCE(MAX(version),0) version FROM schema_migrations")).rows[0]?.version ?? 0);
  if (latest !== migrations.at(-1)?.version) throw new Error("cloud schema version mismatch");
}

async function verify(client: PoolClient, version: number): Promise<void> {
  if (version < 3) return;
  const result = await client.query<{ column_name: string }>(`SELECT column_name FROM information_schema.columns
    WHERE table_schema='public' AND table_name='sessions'`);
  const columns = new Set(result.rows.map(({ column_name }) => column_name));
  for (const required of ["expires_at", "last_seen_at", "revoked_at"]) {
    if (!columns.has(required)) throw new Error(`cloud sessions missing ${required}`);
  }
}
