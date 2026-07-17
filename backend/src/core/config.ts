import { homedir, tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { AppError } from "./errors";

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
	  gachaResourceManifestUrl?: string;
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
	    cloudBaseUrl: (env.MHG_CLOUD_BASE_URL ?? "http://127.0.0.1:3333").replace(/\/+$/, ""),
	    gachaResourceManifestUrl: env.MHG_GACHA_RESOURCE_MANIFEST_URL
	      ?? "https://github.com/HappyDIY/MHGLauncher/releases/latest/download/gacha-history-manifest.json",
	  };
		}

export function validateServerSettings(value: Settings): void {
  if (!value.apiToken.trim()) {
    throw new AppError("api_token_missing", "MHG_API_TOKEN 不能为空", 500);
  }
  if (!Number.isFinite(value.requestTimeout) || value.requestTimeout < 1_000 || value.requestTimeout > 300_000) {
    throw new AppError("request_timeout_invalid", "MHG_REQUEST_TIMEOUT 必须位于 1000 到 300000 毫秒之间", 500);
  }
  let cloudUrl: URL;
  try { cloudUrl = new URL(value.cloudBaseUrl ?? ""); }
  catch { throw new AppError("cloud_url_invalid", "MHG_CLOUD_BASE_URL 必须是有效 URL", 500); }
  if (!["http:", "https:"].includes(cloudUrl.protocol) || cloudUrl.username || cloudUrl.password) {
    throw new AppError("cloud_url_invalid", "MHG_CLOUD_BASE_URL 必须是无凭据的 HTTP 或 HTTPS URL", 500);
  }
  let resourceUrl: URL;
  try { resourceUrl = new URL(value.gachaResourceManifestUrl ?? ""); }
  catch { throw new AppError("gacha_resource_url_invalid", "历史卡池资源地址无效", 500); }
  if (resourceUrl.protocol !== "https:" || resourceUrl.username || resourceUrl.password) {
    throw new AppError("gacha_resource_url_invalid", "历史卡池资源必须使用无凭据的 HTTPS 地址", 500);
  }
}
