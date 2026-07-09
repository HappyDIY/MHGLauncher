import { join } from "node:path";
import type { Settings } from "../core/config";
import { AppError } from "../core/errors";
import type { GameCharacter, GameRole } from "../core/models";
import { Device } from "./device";
import type { GameRecordSource } from "./game-record";
import { sign } from "./signing";

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

  private character(uid: string, value: JSONValue, updatedAt: string, payload: unknown = value): GameCharacter {
    const detail = payload as JSONValue, weapon = (value.weapon ?? detail.weapon) as JSONValue | undefined;
    return { uid, avatar_id: String(value.id), name: String(value.name ?? ""), element: String(value.element ?? ""), level: Number(value.level ?? 0),
      rarity: Number(value.rarity ?? 0), constellation: Number(value.actived_constellation_num ?? 0), fetter: Number(value.fetter ?? 0),
      weapon_name: String(weapon?.name ?? ""), weapon_level: Number(weapon?.level ?? 0), icon_url: String(value.icon ?? "") || null, payload, updated_at: updatedAt };
  }

  private headers(cookie: string, ds: string): Record<string, string> {
    return { Cookie: cookie, DS: ds, "User-Agent": agent, "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "5",
      "x-rpc-device_id": this.device.deviceId, "x-rpc-device_fp": this.device.deviceFP, "Content-Type": "application/json", Referer: "https://app.mihoyo.com" };
  }

  private api(url: string, cookie: string, ds: string, init: RequestInit = {}): Promise<JSONValue> {
    return this.request(url, { ...init, headers: { ...this.headers(cookie, ds), ...init.headers } });
  }

  private async request(url: string, init?: RequestInit): Promise<JSONValue> {
    const response = await fetch(url, { ...init, signal: AbortSignal.timeout(30_000) });
    const payload = await response.json() as JSONValue;
    if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || "米游社请求失败"), 502, { retcode: String(payload.retcode ?? "unknown") });
    return payload.data as JSONValue ?? {};
  }
}
