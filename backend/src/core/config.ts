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
  hutaoApiBaseUrl?: string;
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
    cloudBaseUrl: (env.MHG_CLOUD_BASE_URL ?? "http://localhost:3333").replace(/\/+$/, ""),
    hutaoApiBaseUrl: (env.MHG_HUTAO_API_BASE_URL ?? "https://api.snaphutaorp.org").replace(/\/+$/, ""),
  };
}

export function validateServerSettings(value: Settings): void {
  if (!value.apiToken.trim()) {
    throw new AppError("api_token_missing", "MHG_API_TOKEN 不能为空", 500);
  }
  if (!Number.isFinite(value.requestTimeout) || value.requestTimeout < 1_000 || value.requestTimeout > 300_000) {
    throw new AppError("request_timeout_invalid", "MHG_REQUEST_TIMEOUT 必须位于 1000 到 300000 毫秒之间", 500);
  }
  if (!Number.isInteger(value.downloadWorkers) || value.downloadWorkers < 1 || value.downloadWorkers > 32) {
    throw new AppError("download_workers_invalid", "MHG_DOWNLOAD_WORKERS 必须是 1 到 32 之间的整数", 500);
  }
  if (!Number.isInteger(value.downloadSpeedLimitKB)
    || value.downloadSpeedLimitKB < 0 || value.downloadSpeedLimitKB > 10_000_000) {
    throw new AppError("download_speed_limit_invalid", "MHG_DOWNLOAD_SPEED_LIMIT 必须是有效的非负整数", 500);
  }
  let cloudUrl: URL;
  try { cloudUrl = new URL(value.cloudBaseUrl ?? ""); }
  catch { throw new AppError("cloud_url_invalid", "MHG_CLOUD_BASE_URL 必须是有效 URL", 500); }
  const localHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);
  const secureProtocol = cloudUrl.protocol === "https:"
    || cloudUrl.protocol === "http:" && localHosts.has(cloudUrl.hostname);
  if (!secureProtocol || cloudUrl.username || cloudUrl.password) {
    throw new AppError("cloud_url_invalid", "MHG_CLOUD_BASE_URL 仅允许无凭据的 HTTPS URL，本地回环地址可使用 HTTP", 500);
  }
  let hutaoUrl: URL;
  try { hutaoUrl = new URL(value.hutaoApiBaseUrl ?? "https://api.snaphutaorp.org"); }
  catch { throw new AppError("hutao_api_url_invalid", "MHG_HUTAO_API_BASE_URL 必须是有效 URL", 500); }
  if (hutaoUrl.protocol !== "https:" || hutaoUrl.username || hutaoUrl.password) {
    throw new AppError("hutao_api_url_invalid", "MHG_HUTAO_API_BASE_URL 仅允许无凭据的 HTTPS URL", 500);
  }
}
