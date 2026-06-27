import { join } from "node:path";
import type { Settings } from "../core/config";
import { AppError } from "../core/errors";
import type { CycleKind, CycleRecord, GameCharacter, GameRole, GachaEvent, WishRecord } from "../core/models";
import { Device } from "./device";
import { cycleTitle, type GachaUrlProof, type GameRecordSource } from "./game-record";
import { sign } from "./signing";
import { normalizeWishSyncError } from "./wish-sync";

type JSONValue = Record<string, any>;
const agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1";
const recordRoot = "https://api-takumi-record.mihoyo.com/game_record/app/genshin/api";

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

  async cycles(credential: string, role: GameRole, kind: CycleKind): Promise<CycleRecord[]> {
    if (kind === "abyss") return (await Promise.all([1, 2].map((schedule) => this.abyss(credential, role, schedule)))).filter(Boolean) as CycleRecord[];
    const path = kind === "theatre" ? "role_combat" : "hard_challenge";
    const query = new URLSearchParams({ role_id: role.uid, server: role.region, need_detail: "true", active: "1" });
    const data = await this.api(`${recordRoot}/${path}?${query}`, credential, sign("x4", "", query.toString()), { method: "GET" });
    return (data.data as JSONValue[] ?? [data]).filter((item) => Object.keys(item).length).map((item, index) => this.cycle(role.uid, kind, item, index));
  }

  async gachaEvents(credential: string, _role: GameRole): Promise<GachaEvent[]> {
    const data = await this.api(`${recordRoot}/act_calendar`, credential, sign("x4"), { method: "GET" });
    const now = new Date().toISOString();
    return (data.card_pool_list as JSONValue[] ?? []).map((item, index) => ({
      id: String(item.id ?? `card-${index}`), version: String(item.version ?? ""), gacha_type: String(item.gacha_type ?? ""),
      name: String(item.title ?? item.name ?? "卡池"), started_at: this.time(item.start_timestamp), ended_at: this.time(item.end_timestamp),
      orange_up: this.names(item.r5_up_items), purple_up: this.names(item.r4_up_items), banner_url: String(item.banner ?? "") || null, updated_at: now,
    }));
  }

  async verifyGachaUrl(url: string): Promise<GachaUrlProof> {
    const parsed = new URL(url);
    if (!parsed.hostname.includes("mihoyo.com") || !parsed.searchParams.get("authkey")) throw new AppError("gacha_url_invalid", "抽卡 URL 无效", 422);
    parsed.searchParams.set("size", "20");
    const uid = parsed.searchParams.get("uid") ?? parsed.searchParams.get("game_uid") ?? parsed.searchParams.get("role_id") ?? "";
    let data: JSONValue = {};
    try { data = await this.request(parsed.toString()); } catch (error) { normalizeWishSyncError(error); }
    const records = (data.list as JSONValue[] ?? []).map((item) => this.wish(uid || String(item.uid ?? ""), item));
    const provenUid = uid || records.find((item) => item.uid)?.uid;
    if (!provenUid || records.length === 0) throw new AppError("gacha_url_unverified", "抽卡 URL 可用，但无法确认 UID", 422);
    return { uid: provenUid, records: records.map((item) => ({ ...item, uid: provenUid })) };
  }

  private async abyss(credential: string, role: GameRole, schedule: number): Promise<CycleRecord | null> {
    const query = new URLSearchParams({ role_id: role.uid, server: role.region, schedule_type: String(schedule) });
    const data = await this.api(`${recordRoot}/spiralAbyss?${query}`, credential, sign("x4", "", query.toString()), { method: "GET" });
    return Object.keys(data).length ? this.cycle(role.uid, "abyss", data, schedule) : null;
  }

  private character(uid: string, value: JSONValue, updatedAt: string, payload: unknown = value): GameCharacter {
    const weapon = value.weapon as JSONValue | undefined;
    return { uid, avatar_id: String(value.id), name: String(value.name ?? ""), element: String(value.element ?? ""), level: Number(value.level ?? 0),
      rarity: Number(value.rarity ?? 0), constellation: Number(value.actived_constellation_num ?? 0), fetter: Number(value.fetter ?? 0),
      weapon_name: String(weapon?.name ?? ""), weapon_level: Number(weapon?.level ?? 0), icon_url: String(value.icon ?? "") || null, payload, updated_at: updatedAt };
  }

  private cycle(uid: string, kind: CycleKind, value: JSONValue, fallback: number): CycleRecord {
    const schedule = value.schedule as JSONValue | undefined, stat = value.stat as JSONValue | undefined;
    const scheduleId = String(value.schedule_id ?? schedule?.schedule_id ?? schedule?.id ?? `${kind}-${fallback}`);
    const summary = kind === "abyss" ? `${Number(value.total_star ?? 0)} 星` : `${String(stat?.difficulty_id ?? value.difficulty ?? "") || "当前周期"}`;
    return { uid, kind, schedule_id: scheduleId, title: `${cycleTitle(kind)} ${scheduleId}`, summary, started_at: this.time(schedule?.start_time), ended_at: this.time(schedule?.end_time), uploaded_at: null, payload: value, updated_at: new Date().toISOString() };
  }

  private names(values: JSONValue[] | undefined): string[] { return (values ?? []).map((item) => String(item.name ?? item.item_name ?? "")).filter(Boolean); }
  private time(value: unknown): string { const seconds = Number(value ?? 0); return seconds > 0 ? new Date(seconds * 1000).toISOString() : ""; }
  private wish(uid: string, v: JSONValue): WishRecord { const type = String(v.gacha_type); return { id: String(v.id), uid, gacha_type: type, uigf_gacha_type: type === "400" ? "301" : type, item_id: String(v.item_id), name: String(v.name), item_type: String(v.item_type), rank: Number(v.rank_type), time: String(v.time).replace(" ", "T") }; }
  private headers(cookie: string, ds: string): Record<string, string> { return { Cookie: cookie, DS: ds, "User-Agent": agent, "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "5", "x-rpc-device_id": this.device.deviceId, "x-rpc-device_fp": this.device.deviceFP, "Content-Type": "application/json", Referer: "https://app.mihoyo.com" }; }
  private api(url: string, cookie: string, ds: string, init: RequestInit = {}): Promise<JSONValue> { return this.request(url, { ...init, headers: { ...this.headers(cookie, ds), ...init.headers } }); }
  private async request(url: string, init?: RequestInit): Promise<JSONValue> { const response = await fetch(url, { ...init, signal: AbortSignal.timeout(30_000) }); const payload = await response.json() as JSONValue; if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || "米游社请求失败"), 502, { retcode: String(payload.retcode ?? "unknown") }); return payload.data as JSONValue ?? {}; }
}
