import { Pool } from "pg";
import { migrate } from "./migrations";

declare global { var mhgAdminPool: Pool | undefined; var mhgAdminReady: Promise<void> | undefined }

export function pool(): Pool {
  return globalThis.mhgAdminPool ??= new Pool({ connectionString: process.env.ADMIN_DATABASE_URL, options: "-c timezone=UTC" });
}

export async function ready(): Promise<void> {
  globalThis.mhgAdminReady ??= migrate(pool()).catch((error) => {
    globalThis.mhgAdminReady = undefined;
    throw error;
  });
  return globalThis.mhgAdminReady;
}
