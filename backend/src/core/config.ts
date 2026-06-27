import { homedir, tmpdir } from "node:os";
import { join, resolve } from "node:path";

export interface Settings {
  dataDir: string;
  databasePath: string;
  apiToken: string;
  providerMode: "fixture" | "live";
  fixtureDir: string;
  requestTimeout: number;
  downloadWorkers: number;
  downloadSpeedLimitKB: number;
	  socketPath: string;
	  cloudBaseUrl?: string;
}

function integer(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function settings(env: NodeJS.ProcessEnv = process.env): Settings {
  const dataDir = resolve(env.MHG_DATA_DIR ?? join(homedir(), "Library/Application Support/MHGLauncher"));
  return {
    dataDir,
    databasePath: resolve(env.MHG_DATABASE_PATH ?? join(dataDir, "mhglauncher.db")),
    apiToken: env.MHG_API_TOKEN ?? "",
    providerMode: env.MHG_PROVIDER_MODE === "fixture" ? "fixture" : "live",
    fixtureDir: resolve(env.MHG_FIXTURE_DIR ?? join(dataDir, "fixtures")),
    requestTimeout: integer(env.MHG_REQUEST_TIMEOUT, 30_000),
    downloadWorkers: integer(env.MHG_DOWNLOAD_WORKERS, 4),
    downloadSpeedLimitKB: integer(env.MHG_DOWNLOAD_SPEED_LIMIT, 0),
	    socketPath: resolve(env.MHG_SOCKET_PATH ?? join(tmpdir(), `mhg-${process.pid}.sock`)),
	    cloudBaseUrl: env.MHG_CLOUD_BASE_URL ?? "",
	  };
	}
