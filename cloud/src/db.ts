import { Pool, type PoolClient } from "pg";
import { migrate } from "./migrations";

declare global { var mhgCloudPool: Pool | undefined; var mhgCloudReady: Promise<void> | undefined; }

export function pool(): Pool {
  return globalThis.mhgCloudPool ??= new Pool({ connectionString: process.env.DATABASE_URL, options: "-c timezone=UTC" });
}

export async function ready(): Promise<void> {
  globalThis.mhgCloudReady ??= migrate(pool()).catch((error: unknown) => {
    globalThis.mhgCloudReady = undefined;
    throw error;
  });
  return globalThis.mhgCloudReady;
}

export async function healthy(): Promise<boolean> {
  try { await ready(); await pool().query("SELECT 1"); return true; } catch { return false; }
}

export async function transaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  await ready();
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const client = await pool().connect();
    try {
      await client.query("BEGIN");
      const value = await fn(client);
      await client.query("COMMIT");
      return value;
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      const code = (error as { code?: string }).code;
      if (attempt === 3 || (code !== "40P01" && code !== "40001")) throw error;
      await new Promise((resolve) => setTimeout(resolve, 10 * attempt));
    } finally {
      client.release();
    }
  }
  throw new Error("transaction_retry_exhausted");
}
