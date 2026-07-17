import { join } from "node:path";
import type { Settings } from "../core/config";
import { AppError } from "../core/errors";
import type { GameCharacter, GameRole, GachaEvent, WishRecord } from "../core/models";
import { Device } from "./device";
import type { GachaUrlProof, GameRecordSource } from "./game-record";
import { sign } from "./signing";
import { defaultWishSyncSleeper, normalizeWishSyncError } from "./wish-sync";

type JSONValue = Record<string, any>;
const agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1";
const recordRoot = "https://api-takumi-record.mihoyo.com/game_record/app/genshin/api";
const gachaHosts = new Set(["public-operation-hk4e.mihoyo.com", "webstatic.mihoyo.com"]);
const gachaEndpoint = "https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog";

export class LiveGameRecordSource implements GameRecordSource {
  private readonly device: Device;
  constructor(config: Settings) { this.device = new Device(join(config.dataDir, "device.json")); }

  async characters(credential: string, role: GameRole): Promise<GameCharacter[]> {
    const body = JSON.stringify({ role_id: role.uid, server: role.region, sort_type: 1 });
    const data = await this.api(`${recordRoot}/character/list`, credential, sign("x4", body), { method: "POST", body });
    const now = new Date().toISOString();
    return (data.list as JSONValue[] ?? []).map((item) => this.character(role.uid, item, now));
  }

  async characterDetail(credential: string, role: GameRole, avatarId: string): Promise<GameCharacter> {
    const body = JSON.stringify({ role_id: role.uid, server: role.region, sort_type: 1, character_ids: [Number(avatarId)] });
    const data = await this.api(`${recordRoot}/character/detail`, credential, sign("x4", body), { method: "POST", body });
    const item = (data.list as JSONValue[] | undefined)?.[0] ?? (data.avatars as JSONValue[] | undefined)?.[0];
    if (!item) throw new AppError("character_missing", "角色详情不存在", 404);
    return this.character(role.uid, item.base ?? item, new Date().toISOString(), item);
  }

  async gachaEvents(credential: string, role: GameRole): Promise<GachaEvent[]> {
    const body = JSON.stringify({ role_id: role.uid, server: role.region });
    const data = await this.api(`${recordRoot}/act_calendar`, credential, sign("x4", body), { method: "POST", body });
    const now = new Date().toISOString();
    return (data.card_pool_list as JSONValue[] ?? []).map((item, index) => ({
      id: String(item.id ?? `card-${index}`), version: String(item.version ?? ""), gacha_type: String(item.gacha_type ?? ""),
      name: String(item.title ?? item.name ?? "卡池"), started_at: this.time(item.start_timestamp), ended_at: this.time(item.end_timestamp),
      orange_up: this.names(item.r5_up_items), purple_up: this.names(item.r4_up_items), banner_url: String(item.banner ?? "") || null, updated_at: now,
    }));
  }

  async verifyGachaUrl(url: string): Promise<GachaUrlProof> {
    const parsed = this.gachaRequest(url);
    parsed.searchParams.set("gacha_type", "301");
    parsed.searchParams.set("size", "20");
    parsed.searchParams.set("end_id", "0");
    const uid = parsed.searchParams.get("uid") ?? parsed.searchParams.get("game_uid") ?? parsed.searchParams.get("role_id") ?? "";
    let data: JSONValue = {};
    try { data = await this.request(parsed.toString()); } catch (error) { normalizeWishSyncError(error); }
    const records = (data.list as JSONValue[] ?? []).map((item) => this.wish(uid || String(item.uid ?? ""), item));
    const provenUid = uid || records.find((item) => item.uid)?.uid;
    if (!provenUid || records.length === 0) throw new AppError("gacha_url_unverified", "抽卡 URL 可用，但无法确认 UID", 422);
    return { uid: provenUid, records: records.map((item) => ({ ...item, uid: provenUid })) };
  }

  async *wishesFromGachaUrl(url: string): AsyncIterable<WishRecord[]> {
    const base = this.gachaRequest(url), hintedUid = this.queryUid(base);
    let provenUid = hintedUid, total = 0;
    for (const type of ["100", "200", "301", "302", "500"]) {
      const collected: WishRecord[] = [];
      let end = "0";
      while (true) {
        const request = new URL(base);
        request.searchParams.set("gacha_type", type); request.searchParams.set("size", "20"); request.searchParams.set("end_id", end);
        let data: JSONValue = {};
        try { data = await this.request(request.toString()); } catch (error) { normalizeWishSyncError(error); }
        const values = data.list as JSONValue[] ?? [];
        const records = values.map((item) => this.wish(hintedUid || String(item.uid ?? ""), item));
        const pageUid = records.find((item) => item.uid)?.uid ?? "";
        if (pageUid && provenUid && pageUid !== provenUid) throw new AppError("gacha_uid_mismatch", "抽卡 URL 返回了不一致的 UID", 422);
        provenUid ||= pageUid;
        collected.push(...records.map((item) => ({ ...item, uid: provenUid || item.uid })));
        total += records.length;
        if (total > 50_000) throw new AppError("gacha_record_limit", "抽卡 URL 返回的记录过多", 422);
        await defaultWishSyncSleeper();
        if (records.length < 20) break;
        end = records.at(-1)?.id ?? "0";
      }
      if (collected.length) yield collected;
    }
    if (!provenUid || total === 0) throw new AppError("gacha_url_unverified", "抽卡 URL 可用，但无法确认 UID", 422);
  }

  private gachaRequest(value: string): URL {
    let input: URL;
    try { input = new URL(value); } catch { throw new AppError("gacha_url_invalid", "抽卡 URL 无效", 422); }
    const appId = input.searchParams.get("auth_appid");
    if (!gachaHosts.has(input.hostname) || !input.searchParams.get("authkey") || (appId && appId !== "webview_gacha")) {
      throw new AppError("gacha_url_invalid", "抽卡 URL 无效", 422);
    }
    return new URL(`${gachaEndpoint}?${input.searchParams}`);
  }

  private queryUid(value: URL): string {
    return value.searchParams.get("uid") ?? value.searchParams.get("game_uid") ?? value.searchParams.get("role_id") ?? "";
  }

  private character(uid: string, value: JSONValue, updatedAt: string, payload: unknown = value): GameCharacter {
    const weapon = value.weapon as JSONValue | undefined;
    return { uid, avatar_id: String(value.id), name: String(value.name ?? ""), element: String(value.element ?? ""), level: Number(value.level ?? 0),
      rarity: Number(value.rarity ?? 0), constellation: Number(value.actived_constellation_num ?? 0), fetter: Number(value.fetter ?? 0),
      weapon_name: String(weapon?.name ?? ""), weapon_level: Number(weapon?.level ?? 0), icon_url: String(value.icon ?? "") || null, payload, updated_at: updatedAt };
  }

  private names(values: JSONValue[] | undefined): string[] { return (values ?? []).map((item) => String(item.name ?? item.item_name ?? "")).filter(Boolean); }
  private time(value: unknown): string | null { const seconds = Number(value ?? 0); return seconds > 0 ? new Date(seconds * 1000).toISOString() : null; }
  private wish(uid: string, v: JSONValue): WishRecord { const type = String(v.gacha_type); return { id: String(v.id), uid, gacha_type: type, uigf_gacha_type: type === "400" ? "301" : type, item_id: String(v.item_id), name: String(v.name), item_type: String(v.item_type), rank: Number(v.rank_type), time: String(v.time).replace(" ", "T") }; }
  private headers(cookie: string, ds: string): Record<string, string> { return { Cookie: cookie, DS: ds, "User-Agent": agent, "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "5", "x-rpc-device_id": this.device.deviceId, "x-rpc-device_fp": this.device.deviceFP, "Content-Type": "application/json", Referer: "https://app.mihoyo.com" }; }
  private api(url: string, cookie: string, ds: string, init: RequestInit = {}): Promise<JSONValue> { return this.request(url, { ...init, headers: { ...this.headers(cookie, ds), ...init.headers } }); }
  private async request(url: string, init?: RequestInit): Promise<JSONValue> {
    const response = await fetch(url, { ...init, signal: AbortSignal.timeout(30_000) });
    let payload: JSONValue;
    try { payload = JSON.parse(await response.text()) as JSONValue; }
    catch { throw new AppError("mihoyo_response_invalid", `米游社请求失败（HTTP ${response.status}）`, 502, { http_status: String(response.status) }); }
    if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || "米游社请求失败"), 502, { retcode: String(payload.retcode ?? "unknown") });
    return payload.data as JSONValue ?? {};
  }
}
