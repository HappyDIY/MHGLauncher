import { Pool, type PoolClient } from "pg";

const schema = `
CREATE TABLE IF NOT EXISTS users(uid TEXT PRIMARY KEY,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,reverified_at TIMESTAMPTZ NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS gacha_records(uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,id TEXT NOT NULL,gacha_type TEXT NOT NULL,uigf_gacha_type TEXT NOT NULL,item_id TEXT NOT NULL,name TEXT NOT NULL,item_type TEXT NOT NULL,rank INTEGER NOT NULL,time TIMESTAMPTZ NOT NULL,payload JSONB NOT NULL,PRIMARY KEY(uid,id));
CREATE TABLE IF NOT EXISTS cycle_records(uid TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,kind TEXT NOT NULL,schedule_id TEXT NOT NULL,payload JSONB NOT NULL,uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),PRIMARY KEY(uid,kind,schedule_id));
`;

declare global { var mhgCloudPool: Pool | undefined; var mhgCloudReady: Promise<void> | undefined; }

export function pool(): Pool {
  return globalThis.mhgCloudPool ??= new Pool({ connectionString: process.env.DATABASE_URL });
}

export async function ready(): Promise<void> {
  globalThis.mhgCloudReady ??= pool().query(schema).then(() => undefined);
  return globalThis.mhgCloudReady;
}

export async function transaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  await ready();
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const value = await fn(client);
    await client.query("COMMIT");
    return value;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
