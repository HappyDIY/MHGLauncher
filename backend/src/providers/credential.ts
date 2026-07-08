import { AppError } from "../core/errors";
import { cookies, sign } from "./signing";

type JSONValue = Record<string, any>;

export async function completeCredential(value: string, deviceId = ""): Promise<string> {
  const map = cookies(value);
  if (map.get("stoken")) {
    await fillCookieToken(map, deviceId);
    await fillLToken(map, deviceId);
  }
  return serialize(map);
}

export async function gameRecordCredential(value: string, deviceId = ""): Promise<string> {
  const map = cookies(await completeCredential(value, deviceId));
  const pairs: [string, string][] = [];
  for (const key of ["account_id", "cookie_token", "ltoken", "ltuid"]) {
    const item = map.get(key); if (item) pairs.push([key, item]);
  }
  return serialize(new Map(pairs));
}

async function fillCookieToken(map: Map<string, string>, deviceId: string): Promise<void> {
  if (map.get("cookie_token") && map.get("account_id")) return;
  const data = await passport("https://passport-api.mihoyo.com/account/auth/api/getCookieAccountInfoBySToken", map, deviceId);
  map.set("cookie_token", String(data.cookie_token)); map.set("account_id", String(data.uid));
}

async function fillLToken(map: Map<string, string>, deviceId: string): Promise<void> {
  if (map.get("ltoken") && map.get("ltuid")) return;
  const data = await passport("https://passport-api.mihoyo.com/account/auth/api/getLTokenBySToken", map, deviceId);
  map.set("ltoken", String(data.ltoken)); map.set("ltuid", map.get("stuid") ?? map.get("account_id") ?? "");
}

async function passport(url: string, map: Map<string, string>, deviceId: string): Promise<JSONValue> {
  const response = await fetch(url, { headers: { Cookie: serialize(map), DS: sign("prod"), "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1", "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "2", "x-rpc-device_id": deviceId, "Content-Type": "application/json" }, signal: AbortSignal.timeout(30_000) });
  const payload = await response.json() as JSONValue;
  if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || `米游社请求失败（错误码 ${payload.retcode ?? "未知"}）`), 502, { retcode: String(payload.retcode ?? "unknown") });
  return payload.data as JSONValue ?? {};
}

function serialize(map: Map<string, string>): string {
  return [...map].filter(([, v]) => v).map(([k, v]) => `${k}=${v}`).join(";");
}
