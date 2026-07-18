import type { Pool } from "pg";

const statements = [
  "CREATE SCHEMA IF NOT EXISTS admin",
  `CREATE TABLE IF NOT EXISTS admin.schema_migrations(
    version INTEGER PRIMARY KEY,applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
  `CREATE TABLE IF NOT EXISTS admin.owner(
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK(id=1),email TEXT NOT NULL UNIQUE,password_hash TEXT NOT NULL,
    totp_secret TEXT NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
  `CREATE TABLE IF NOT EXISTS admin.admin_sessions(
    token_hash TEXT PRIMARY KEY,owner_id SMALLINT NOT NULL REFERENCES admin.owner(id) ON DELETE CASCADE,
    csrf_token TEXT NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,revoked_at TIMESTAMPTZ)`,
  `CREATE TABLE IF NOT EXISTS admin.recovery_codes(
    code_hash TEXT PRIMARY KEY,owner_id SMALLINT NOT NULL REFERENCES admin.owner(id) ON DELETE CASCADE,used_at TIMESTAMPTZ)`,
  `CREATE TABLE IF NOT EXISTS admin.login_attempts(
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,email_hash TEXT NOT NULL,source_hash TEXT NOT NULL,
    succeeded BOOLEAN NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
  `CREATE INDEX IF NOT EXISTS login_attempts_lookup ON admin.login_attempts(email_hash,source_hash,created_at DESC)`,
  `CREATE TABLE IF NOT EXISTS admin.auth_audit_events(
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,action TEXT NOT NULL,result TEXT NOT NULL,
    source_hash TEXT NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
];

export async function migrate(database: Pool): Promise<void> {
  const client = await database.connect();
  try {
    await client.query("BEGIN");
    for (const statement of statements) await client.query(statement);
    await client.query("INSERT INTO admin.schema_migrations(version) VALUES(1) ON CONFLICT DO NOTHING");
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally { client.release(); }
}
