import { join } from "node:path";
import type { Settings } from "../core/config";
import { AppError } from "../core/errors";
import type { AccountIdentity, DailyNote, GameRole, QRSession, WishRecord } from "../core/models";
import { Device } from "./device";
import type { GameBuild, Provider } from "./provider";
import { Sophon } from "./sophon";
import { cookies, sign } from "./signing";

type JSONValue = Record<string, any>;
const agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1";

export class LiveProvider implements Provider {
  private readonly device: Device; private readonly sophon = new Sophon(); private readonly sessions = new Map<string, QRSession>();
  constructor(config: Settings) { this.device = new Device(join(config.dataDir, "device.json")); }

  async createQRSession(): Promise<QRSession> {
    const data = await this.request("https://passport-api.mihoyo.com/account/ma-cn-passport/app/createQRLogin", { method: "POST", headers: this.qrHeaders(), body: "{}" });
    const value = { id: String(data.ticket), url: String(data.url), status: "created", expires_at: new Date(Date.now() + 300_000).toISOString() } satisfies QRSession;
    this.sessions.set(value.id, value); return value;
  }

  async queryQRSession(id: string): Promise<[QRSession, AccountIdentity | null]> {
    const data = await this.request("https://passport-api.mihoyo.com/account/ma-cn-passport/app/queryQRLoginStatus", { method: "POST", headers: this.qrHeaders(), body: JSON.stringify({ ticket: id }) });
    const prior = this.sessions.get(id); if (!prior) throw new AppError("qr_session_missing", "二维码会话不存在", 404);
    const raw = String(data.status).toLowerCase(); const status = ["confirmed", "3"].includes(raw) ? "confirmed" : ["scanned", "2"].includes(raw) ? "scanned" : ["expired", "4"].includes(raw) ? "expired" : "created";
    const session: QRSession = { ...prior, status }; if (status !== "confirmed") return [session, null];
    const token = (data.tokens as JSONValue[] | undefined)?.find((value) => value.token_type === 1)?.token;
    const user = data.user_info as JSONValue | undefined; if (!user || !token) throw new AppError("qr_payload_invalid", "二维码登录结果缺少凭据", 502);
    let credential = `stuid=${user.aid}; stoken=${token}; mid=${user.mid}`; credential = await this.enrichCredential(credential);
    return [session, { aid: String(user.aid), mid: String(user.mid), nickname: String(user.account_name || "米游社用户"), credential }];
  }

  async getRoles(credential: string): Promise<GameRole[]> {
    const data = await this.api("https://api-takumi.mihoyo.com/binding/api/getUserGameRolesByStoken", credential, sign("lk2", "", "", 1));
    return (data.list as JSONValue[] ?? []).filter((v) => v.game_biz === "hk4e_cn").map((v) => ({ uid: String(v.game_uid), nickname: String(v.nickname), region: String(v.region), level: Number(v.level), selected: Boolean(v.is_chosen) }));
  }

  getBuild(version = ""): Promise<GameBuild> { return this.sophon.build(version); }

  async *wishes(credential: string, role: GameRole, newest: Record<string, string>): AsyncIterable<WishRecord[]> {
    const authkey = await this.authkey(credential, role);
    for (const type of ["100", "200", "301", "302"]) {
      let end = "0"; while (true) {
        const query = new URLSearchParams({ auth_appid: "webview_gacha", authkey_ver: "1", sign_type: "2", authkey, lang: "zh-cn", gacha_type: type, size: "20", end_id: end });
        const data = await this.request(`https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog?${query}`);
        const records = (data.list as JSONValue[] ?? []).map((v) => this.wish(role.uid, v)); const checkpoint = newest[type]; const index = checkpoint ? records.findIndex((v) => v.id === checkpoint) : -1;
        const fresh = index < 0 ? records : records.slice(0, index); if (fresh.length) yield fresh; if (fresh.length < records.length || records.length < 20) break; end = records.at(-1)?.id ?? "0";
      }
    }
  }

  async getDailyNote(credential: string, role: GameRole, challenge = ""): Promise<DailyNote> {
    await this.device.fingerprint(); const query = new URLSearchParams({ role_id: role.uid, server: role.region }).toString();
    const headers = this.headers(credential, sign("x4", "", query)); if (challenge) headers["x-rpc-challenge"] = challenge;
    const url = `https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/dailyNote?${query}`;
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(30_000) }), payload = await response.json() as JSONValue;
    if (Number(payload.retcode) === 1034) throw new AppError("verification_required", "请完成人机验证后重试", 428, await this.createVerification(credential));
    if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || "米游社请求失败"), 502);
    const data = payload.data as JSONValue ?? {};
    const expeditions = data.expeditions as JSONValue[] ?? [], recovery = (data.transformer as JSONValue | undefined)?.recovery_time as JSONValue | undefined;
    return { uid: role.uid, current_resin: Number(data.current_resin ?? 0), max_resin: Number(data.max_resin ?? 200), finished_tasks: Number(data.finished_task_num ?? 0), total_tasks: Number(data.total_task_num ?? 4),
      expeditions_finished: expeditions.filter((v) => v.status === "Finished").length, expeditions_total: Number(data.max_expedition_num ?? expeditions.length), current_home_coin: Number(data.current_home_coin ?? 0),
      max_home_coin: Number(data.max_home_coin ?? 0), weekly_boss_remaining: Number(data.remain_resin_discount_num ?? 0), transformer_ready: Boolean(recovery?.reached), refreshed_at: new Date().toISOString() };
  }

  async verifyNoteChallenge(credential: string, challenge: string, validate: string): Promise<string> {
    const body = JSON.stringify({ geetest_challenge: challenge, geetest_validate: validate, geetest_seccode: `${validate}|jordan` });
    const data = await this.api("https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/verifyVerification", credential, sign("x4", body), { method: "POST", body });
    return String(data.challenge);
  }

  private async enrichCredential(value: string): Promise<string> { const data = await this.api("https://passport-api.mihoyo.com/account/auth/api/getCookieAccountInfoBySToken", value, sign("prod", "{}")); const map = cookies(value); map.set("cookie_token", String(data.cookie_token)); map.set("account_id", String(data.uid)); return [...map].map(([k, v]) => `${k}=${v}`).join("; "); }
  private async createVerification(value: string): Promise<Record<string, string>> { const query = "is_high=true", data = await this.api(`https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/createVerification?${query}`, value, sign("x4", "", query)); return { gt: String(data.gt), challenge: String(data.challenge) }; }
  private async authkey(value: string, role: GameRole): Promise<string> { const body = JSON.stringify({ auth_appid: "webview_gacha", game_biz: "hk4e_cn", game_uid: Number(role.uid), region: role.region }); return String((await this.api("https://api-takumi.mihoyo.com/binding/api/genAuthKey", value, sign("lk2", "", "", 1), { method: "POST", body })).authkey); }
  private wish(uid: string, v: JSONValue): WishRecord { const type = String(v.gacha_type); return { id: String(v.id), uid, gacha_type: type, uigf_gacha_type: type === "400" ? "301" : type, item_id: String(v.item_id), name: String(v.name), item_type: String(v.item_type), rank: Number(v.rank_type), time: String(v.time).replace(" ", "T") }; }
  private headers(cookie: string, ds: string): Record<string, string> { return { Cookie: cookie, DS: ds, "User-Agent": agent, "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "5", "x-rpc-device_id": this.device.deviceId, "x-rpc-device_fp": this.device.deviceFP, "Content-Type": "application/json" }; }
  private qrHeaders(): Record<string, string> { return { "User-Agent": "HYPContainer/1.1.4.133", "x-rpc-app_id": "ddxf5dufpuyo", "x-rpc-client_type": "3", "x-rpc-device_id": this.device.deviceId, "Content-Type": "application/json" }; }
  private api(url: string, cookie: string, ds: string, init: RequestInit = {}): Promise<JSONValue> { return this.request(url, { ...init, headers: { ...this.headers(cookie, ds), ...init.headers } }); }
  private async request(url: string, init?: RequestInit): Promise<JSONValue> { const response = await fetch(url, { ...init, signal: AbortSignal.timeout(30_000) }); const payload = await response.json() as JSONValue; if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || `米游社请求失败（错误码 ${payload.retcode ?? "未知"}）`), 502, { retcode: String(payload.retcode ?? "unknown") }); return payload.data as JSONValue ?? {}; }
}
