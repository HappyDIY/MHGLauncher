import { join } from "node:path";
import { publicEncrypt } from "node:crypto";
import type { Settings } from "../core/config";
import { AppError } from "../core/errors";
import type { AccountIdentity, DailyNote, GameRole, MobileCaptchaSession, QRSession, WishRecord } from "../core/models";
import { Device } from "./device";
import type { GameBuild, Provider } from "./provider";
import { Sophon } from "./sophon";
import { cookies, sign } from "./signing";
import { createAigisHeader, parseAigisSession, type AigisSession, verificationFromAigis } from "./aigis";
import { qrConfirmedPayload, qrStatus } from "./qr";
import { defaultWishSyncSleeper, normalizeWishSyncError, type WishSyncSleeper } from "./wish-sync";

type JSONValue = Record<string, any>;
const agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1";
const passportKey = `-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDDvekdPMHN3AYhm/vktJT+YJr7
cI5DcsNKqdsx5DZX0gDuWFuIjzdwButrIYPNmRJ1G8ybDIF7oDW2eEpm5sMbL9zs
9ExXCdvqrn51qELbqj0XxtMTIpaCHFSI50PfPpTFV9Xt/hmyVwokoOXFlAEgCn+Q
CgGs52bFoYMtyi+xEQIDAQAB
-----END PUBLIC KEY-----`;

export class LiveProvider implements Provider {
  private readonly device: Device; private readonly sophon = new Sophon(); private readonly sessions = new Map<string, QRSession>(); private readonly aigisSessions = new Map<string, AigisSession>();
  constructor(config: Settings, private readonly wishSleep: WishSyncSleeper = defaultWishSyncSleeper) { this.device = new Device(join(config.dataDir, "device.json")); }

  async createQRSession(): Promise<QRSession> {
    const data = await this.request("https://passport-api.mihoyo.com/account/ma-cn-passport/app/createQRLogin", { method: "POST", headers: this.qrHeaders(), body: "{}" });
    const value = { id: String(data.ticket), url: String(data.url), status: "created", expires_at: new Date(Date.now() + 300_000).toISOString() } satisfies QRSession;
    this.sessions.set(value.id, value); return value;
  }

  async queryQRSession(id: string): Promise<[QRSession, AccountIdentity | null]> {
    const data = await this.request("https://passport-api.mihoyo.com/account/ma-cn-passport/app/queryQRLoginStatus", { method: "POST", headers: this.qrHeaders(), body: JSON.stringify({ ticket: id }) });
    const prior = this.sessions.get(id); if (!prior) throw new AppError("qr_session_missing", "二维码会话不存在", 404);
    const status = qrStatus(data);
    const session: QRSession = prior.status === "confirmed" && status !== "confirmed" ? prior : { ...prior, status };
    this.sessions.set(id, session); if (session.status !== "confirmed" || status !== "confirmed") return [session, null];
    const { user, token } = qrConfirmedPayload(data);
    return [session, await this.identity(user, String(token))];
  }

  async identifyCredential(credential: string): Promise<AccountIdentity> {
    return this.identityFromCredential(await this.enrichCredential(await this.normalizeCredential(credential), true));
  }

  async createMobileCaptcha(mobile: string): Promise<MobileCaptchaSession> {
    return this.createMobileCaptchaWithAigis(mobile, "");
  }

  async verifyMobileCaptcha(mobile: string, sessionId: string, challenge: string, validate: string): Promise<MobileCaptchaSession> {
    if (!this.aigisSessions.has(sessionId)) throw new AppError("aigis_session_missing", "验证码验证会话不存在或已过期", 404);
    const session = await this.createMobileCaptchaWithAigis(mobile, createAigisHeader(sessionId, challenge, validate));
    this.aigisSessions.delete(sessionId); return session;
  }

  private async createMobileCaptchaWithAigis(mobile: string, aigis: string): Promise<MobileCaptchaSession> {
    const body = JSON.stringify({ area_code: this.encrypt("+86"), mobile: this.encrypt(mobile) });
    const response = await fetch("https://passport-api.mihoyo.com/account/ma-cn-verifier/verifier/createLoginCaptcha", {
      method: "POST", headers: { ...this.passportHeaders("", sign("prod", body)), "x-rpc-aigis": aigis }, body, signal: AbortSignal.timeout(30_000),
    });
    const payload = await response.json() as JSONValue;
    const rawAigis = response.headers.get("x-rpc-aigis");
    const aigisSession = parseAigisSession(rawAigis);
    if (aigisSession) {
      this.aigisSessions.set(aigisSession.session_id, aigisSession);
      throw new AppError("verification_required", "请完成人机验证后重试", 428, { ...verificationFromAigis(aigisSession) });
    }
    if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || "验证码发送失败"), 502);
    const data = payload.data as JSONValue ?? {};
    return { mobile, action_type: String(data.action_type), countdown: Number(data.countdown ?? 60), aigis: rawAigis };
  }

  async loginByMobileCaptcha(mobile: string, captcha: string, actionType: string, aigis?: string | null): Promise<AccountIdentity> {
    const body = JSON.stringify({ area_code: this.encrypt("+86"), action_type: actionType, captcha, mobile: this.encrypt(mobile) });
    const headers = this.passportHeaders("", sign("prod", body)); if (aigis) headers["x-rpc-aigis"] = aigis;
    const data = await this.request("https://passport-api.mihoyo.com/account/ma-cn-passport/app/loginByMobileCaptcha", { method: "POST", headers, body });
    const token = (data.token as JSONValue | undefined)?.token;
    const user = data.user_info as JSONValue | undefined;
    if (!user || !token) throw new AppError("login_payload_invalid", "短信登录结果缺少凭据", 502);
    return this.identity(user, String(token));
  }

  async getRoles(credential: string): Promise<GameRole[]> {
    const data = await this.api("https://api-takumi.mihoyo.com/binding/api/getUserGameRolesByStoken", credential, sign("lk2", "", "", 1), { headers: { Referer: "https://app.mihoyo.com" } });
    return (data.list as JSONValue[] ?? []).filter((v) => v.game_biz === "hk4e_cn").map((v) => ({ uid: String(v.game_uid), nickname: String(v.nickname), region: String(v.region), level: Number(v.level), selected: Boolean(v.is_chosen) }));
  }

  getBuild(version = "", audioLanguages?: string[]): Promise<GameBuild> { return this.sophon.build(version, audioLanguages); }

  async *wishes(credential: string, role: GameRole, newest: Record<string, string>): AsyncIterable<WishRecord[]> {
    let authkey = "";
    try { authkey = await this.authkey(credential, role); } catch (error) { normalizeWishSyncError(error); }
    for (const type of ["100", "200", "301", "302"]) {
      const collected: WishRecord[] = [];
      let end = "0"; while (true) {
        const query = new URLSearchParams({ auth_appid: "webview_gacha", authkey_ver: "1", sign_type: "2", authkey, lang: "zh-cn", gacha_type: type, size: "20", end_id: end });
        let data: JSONValue = {};
        try { data = await this.request(`https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog?${query}`); } catch (error) { normalizeWishSyncError(error); }
        const records = (data.list as JSONValue[] ?? []).map((v) => this.wish(role.uid, v)); const checkpoint = newest[type]; const index = checkpoint ? records.findIndex((v) => v.id === checkpoint) : -1;
        const fresh = index < 0 ? records : records.slice(0, index); collected.push(...fresh); await this.wishSleep();
        if (fresh.length < records.length || records.length < 20) break; end = records.at(-1)?.id ?? "0";
      }
      if (collected.length) yield collected;
      await this.wishSleep();
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

  private async identity(user: JSONValue, token: string): Promise<AccountIdentity> { const credential = await this.enrichCredential(`stuid=${user.aid}; stoken=${token}; mid=${user.mid}`); return { aid: String(user.aid), mid: String(user.mid ?? ""), nickname: String(user.account_name || "米游社用户"), credential }; }
  private async identityFromCredential(credential: string): Promise<AccountIdentity> { const map = cookies(credential), aid = map.get("stuid") ?? map.get("account_id") ?? "", mid = map.get("mid") ?? ""; if (!aid || !map.get("stoken")) throw new AppError("credential_invalid", "Cookie 缺少 stuid/stoken，或 login_ticket/login_uid", 422); return { aid, mid, nickname: "米游社用户", credential }; }
  private async normalizeCredential(value: string): Promise<string> {
    const map = cookies(value); if (map.get("stoken")) return this.serialize(map);
    const ticket = map.get("login_ticket"), uid = map.get("login_uid");
    if (!ticket || !uid) throw new AppError("credential_invalid", "Cookie 缺少 stuid/stoken，或 login_ticket/login_uid", 422);
    const query = new URLSearchParams({ login_ticket: ticket, uid, token_types: "3" });
    const data = await this.request(`https://api-takumi.mihoyo.com/auth/api/getMultiTokenByLoginTicket?${query}`);
    const stoken = (data.list as JSONValue[] | undefined)?.find((item) => item.name === "stoken")?.token;
    if (!stoken) throw new AppError("credential_invalid", "Cookie 登录票据无法换取 stoken，请重新获取 Cookie", 422);
    map.set("stuid", uid); map.set("stoken", String(stoken)); return this.serialize(map);
  }
  private async enrichCredential(value: string, cookieImport = false): Promise<string> {
    try {
      const data = await this.request("https://passport-api.mihoyo.com/account/auth/api/getCookieAccountInfoBySToken", { headers: this.passportHeaders(value, sign("prod")) });
      const map = cookies(value); map.set("cookie_token", String(data.cookie_token)); map.set("account_id", String(data.uid)); return this.serialize(map);
    } catch (error) {
      if (cookieImport && error instanceof AppError && error.code === "mihoyo_error") throw new AppError("credential_expired", "米游社返回登录状态失效，请重新获取 Cookie 后重试", 401, error.details);
      throw error;
    }
  }
  private async createVerification(value: string): Promise<Record<string, string>> { const query = "is_high=true", data = await this.api(`https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/createVerification?${query}`, value, sign("x4", "", query)); return { gt: String(data.gt), challenge: String(data.challenge) }; }
  private async authkey(value: string, role: GameRole): Promise<string> { const body = JSON.stringify({ auth_appid: "webview_gacha", game_biz: "hk4e_cn", game_uid: Number(role.uid), region: role.region }); return String((await this.api("https://api-takumi.mihoyo.com/binding/api/genAuthKey", value, sign("lk2", "", "", 1), { method: "POST", body })).authkey); }
  private wish(uid: string, v: JSONValue): WishRecord { const type = String(v.gacha_type); return { id: String(v.id), uid, gacha_type: type, uigf_gacha_type: type === "400" ? "301" : type, item_id: String(v.item_id), name: String(v.name), item_type: String(v.item_type), rank: Number(v.rank_type), time: String(v.time).replace(" ", "T") }; }
  private headers(cookie: string, ds: string): Record<string, string> { return { Cookie: cookie, DS: ds, "User-Agent": agent, "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "5", "x-rpc-device_id": this.device.deviceId, "x-rpc-device_fp": this.device.deviceFP, "Content-Type": "application/json" }; }
  private passportHeaders(cookie: string, ds: string): Record<string, string> {
    return {
      Cookie: cookie, DS: ds, "User-Agent": agent, "x-rpc-aigis": "", "x-rpc-app_id": "bll8iq97cem8",
      "x-rpc-app_version": "2.95.1", "x-rpc-client_type": "2", "x-rpc-device_id": this.device.deviceId,
      "x-rpc-device_name": "", "x-rpc-game_biz": "bbs_cn", "x-rpc-sdk_version": "2.16.0",
      "Content-Type": "application/json",
    };
  }
  private qrHeaders(): Record<string, string> { return { "User-Agent": "HYPContainer/1.1.4.133", "x-rpc-app_id": "ddxf5dufpuyo", "x-rpc-client_type": "3", "x-rpc-device_id": this.device.loginDeviceId, "Content-Type": "application/json" }; }
  private api(url: string, cookie: string, ds: string, init: RequestInit = {}): Promise<JSONValue> { return this.request(url, { ...init, headers: { ...this.headers(cookie, ds), ...init.headers } }); }
  private async request(url: string, init?: RequestInit): Promise<JSONValue> { const response = await fetch(url, { ...init, signal: AbortSignal.timeout(30_000) }); const payload = await response.json() as JSONValue; if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || `米游社请求失败（错误码 ${payload.retcode ?? "未知"}）`), 502, { retcode: String(payload.retcode ?? "unknown") }); return payload.data as JSONValue ?? {}; }
  private serialize(map: Map<string, string>): string { return [...map].map(([k, v]) => `${k}=${v}`).join("; "); }
  private encrypt(value: string): string { return publicEncrypt({ key: passportKey, padding: 1 }, Buffer.from(value)).toString("base64"); }
}
