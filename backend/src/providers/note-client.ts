import { AppError } from "../core/errors";
import type { DailyNote, GameRole } from "../core/models";
import type { Device } from "./device";
import { gameRecordCredential } from "./credential";
import { sign } from "./signing";

type JSONValue = Record<string, any>;
const notePath = "/game_record/app/genshin/api/dailyNote";
const indexPath = "/game_record/app/genshin/api/index";

export async function getLiveDailyNote(credential: string, role: GameRole, device: Device, challenge = "", path = ""): Promise<DailyNote> {
  await device.fingerprint(); const query = new URLSearchParams({ role_id: role.uid, server: role.region }).toString(), cookie = await gameRecordCredential(credential, device.deviceId);
  await requestIndex(cookie, query, device, path === indexPath ? challenge : "");
  const payload = await requestRaw(`https://api-takumi-record.mihoyo.com${notePath}?${query}`, noteHeaders(cookie, query, device, path === notePath ? challenge : "", "", "", true));
  const retcode = Number(payload.retcode ?? 0), message = String(payload.message ?? "");
  if (retcode === 1034 || retcode === 5003) {
    if (path === notePath && challenge) throw new AppError("note_verification_failed", "实时便笺验证未通过或已失效，请重新刷新后再验证", 429, { retcode: String(retcode) });
    throw new AppError("verification_required", "请完成人机验证后重试", 428, await createVerification(credential, device, notePath));
  }
  if (retcode === 10306) throw new AppError("verification_required", "验证已失效，请重新完成人机验证", 428, await createVerification(credential, device, notePath));
  if ([10102, 10103, 10104].includes(retcode)) throw new AppError("note_unavailable", message || "实时便笺当前不可用，请检查米游社数据公开或账号状态", 403, { retcode: String(retcode) });
  if (message.toLowerCase().includes("visit too frequently")) throw new AppError("note_sync_limited", "访问过于频繁，请稍后再刷新实时便笺", 429, { retcode: String(retcode || "unknown") });
  if (retcode !== 0) throw new AppError("mihoyo_error", message || `米游社请求失败（错误码 ${payload.retcode ?? "未知"}）`, 502, { retcode: String(payload.retcode ?? "unknown") });
  return normalizeNote(role.uid, payload.data as JSONValue ?? {});
}

export async function verifyNoteChallenge(credential: string, device: Device, challenge: string, validate: string, path = notePath): Promise<string> {
  path ||= notePath;
  const body = JSON.stringify({ geetest_challenge: challenge, geetest_validate: validate, geetest_seccode: `${validate}|jordan` }), cookie = await gameRecordCredential(credential, device.deviceId);
  const data = await request(`https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/verifyVerification`, noteHeaders(cookie, "", device, "", path, body), { method: "POST", body });
  return String(data.challenge);
}

async function requestIndex(cookie: string, query: string, device: Device, challenge: string): Promise<void> {
  const payload = await requestRaw(`https://api-takumi-record.mihoyo.com${indexPath}?${query}`, noteHeaders(cookie, query, device, challenge));
  const retcode = Number(payload.retcode ?? 0);
  if (retcode === 1034 || retcode === 5003) {
    if (challenge) throw new AppError("note_verification_failed", "战绩首页验证未通过或已失效，请重新刷新后再验证", 429, { retcode: String(retcode) });
    throw new AppError("verification_required", "请完成人机验证后重试", 428, await createVerification(cookie, device, indexPath, false));
  }
  if (retcode === 10306) throw new AppError("verification_required", "验证已失效，请重新完成人机验证", 428, await createVerification(cookie, device, indexPath, false));
  if (retcode !== 0) throw new AppError("mihoyo_error", String(payload.message || `米游社请求失败（错误码 ${payload.retcode ?? "未知"}）`), 502, { retcode: String(payload.retcode ?? "unknown") });
}

async function createVerification(credential: string, device: Device, path: string, complete = true): Promise<Record<string, string>> {
  const query = "is_high=true", cookie = complete ? await gameRecordCredential(credential, device.deviceId) : credential;
  const data = await request(`https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/createVerification?${query}`, noteHeaders(cookie, query, device, "", path));
  return { gt: String(data.gt), challenge: String(data.challenge), xrpc_challenge_path: path };
}

async function request(url: string, headers: Record<string, string>, init: RequestInit = {}): Promise<JSONValue> {
  const payload = await requestRaw(url, headers, init);
  if (Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || `米游社请求失败（错误码 ${payload.retcode ?? "未知"}）`), 502, { retcode: String(payload.retcode ?? "unknown") });
  return payload.data as JSONValue ?? {};
}

async function requestRaw(url: string, headers: Record<string, string>, init: RequestInit = {}): Promise<JSONValue> {
  const response = await fetch(url, { ...init, headers: { ...headers, ...init.headers }, signal: AbortSignal.timeout(30_000) });
  if (!response.ok) throw new AppError("mihoyo_error", `米游社请求失败（HTTP ${response.status}）`, 502, { retcode: "http_error" });
  return await response.json() as JSONValue;
}

function noteHeaders(cookie: string, query: string, device: Device, challenge = "", path = "", body = "", toolVersion = false): Record<string, string> {
  const headers: Record<string, string> = { Cookie: cookie, DS: sign("x4", body, query), "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1", Accept: "application/json", "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "5", "x-rpc-device_id": device.deviceId, "x-rpc-device_fp": device.deviceFP, Referer: "https://webstatic.mihoyo.com" };
  if (path) { headers["x-rpc-challenge_game"] = "2"; headers["x-rpc-challenge_path"] = path; }
  if (body) headers["Content-Type"] = "application/json";
  if (toolVersion) headers["x-rpc-tool_verison"] = "v5.0.1-ys";
  if (challenge) headers["x-rpc-challenge"] = challenge;
  return headers;
}

function normalizeNote(uid: string, data: JSONValue): DailyNote {
  const expeditions = data.expeditions as JSONValue[] ?? [], recovery = (data.transformer as JSONValue | undefined)?.recovery_time as JSONValue | undefined;
  return { uid, current_resin: Number(data.current_resin ?? 0), max_resin: Number(data.max_resin ?? 200), finished_tasks: Number(data.finished_task_num ?? 0), total_tasks: Number(data.total_task_num ?? 4),
    expeditions_finished: expeditions.filter((v) => v.status === "Finished").length, expeditions_total: Number(data.max_expedition_num ?? expeditions.length), current_home_coin: Number(data.current_home_coin ?? 0),
    max_home_coin: Number(data.max_home_coin ?? 0), weekly_boss_remaining: Number(data.remain_resin_discount_num ?? 0), transformer_ready: Boolean(recovery?.reached), refreshed_at: new Date().toISOString() };
}
