import { join } from "node:path";
import { publicEncrypt } from "node:crypto";
import type { Settings } from "../core/config";
import { AppError } from "../core/errors";
import type { AccountIdentity, DailyNote, GameRole, MobileCaptchaSession, QRSession, WishRecord } from "../core/models";
import { Device } from "./device";
import { completeCredential } from "./credential";
import { getLiveDailyNote, verifyNoteChallenge as verifyLiveNoteChallenge } from "./note-client";
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
  private readonly device: Device; private readonly sophon = new Sophon(); private readonly sessions = new Map<string, QRSession>();
  private readonly aigisSessions = new Map<string, { session: AigisSession; mobile: string; expires: number }>();
  constructor(config: Settings, private readonly wishSleep: WishSyncSleeper = defaultWishSyncSleeper) { this.device = new Device(join(config.dataDir, "device.json")); }

  async createQRSession(): Promise<QRSession> {
    const data = await this.request("https://passport-api.mihoyo.com/account/ma-cn-passport/app/createQRLogin", { method: "POST", headers: this.qrHeaders(), body: "{}" });
    const value = { id: String(data.ticket), url: String(data.url), status: "created", expires_at: new Date(Date.now() + 300_000).toISOString() } satisfies QRSession;
    this.sessions.set(value.id, value); return value;
  }

  async queryQRSession(id: string): Promise<[QRSession, AccountIdentity | null]> {
    const response = await fetch("https://passport-api.mihoyo.com/account/ma-cn-passport/app/queryQRLoginStatus", {
      method: "POST", headers: this.qrHeaders(), body: JSON.stringify({ ticket: id }), signal: AbortSignal.timeout(30_000),
    });
    const payload = await response.json() as JSONValue;
    const prior = this.sessions.get(id); if (!prior) throw new AppError("qr_session_missing", "二维码会话不存在", 404);
    if (Number(payload.retcode) === -3501) {
      const session: QRSession = { ...prior, status: "expired" }; this.sessions.set(id, session); return [session, null];
    }
    if (!response.ok || Number(payload.retcode ?? 0) !== 0) throw new AppError("mihoyo_error", String(payload.message || "二维码状态查询失败"), 502, { retcode: String(payload.retcode ?? "unknown") });
    const data = payload.data as JSONValue ?? {};
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
    const pending = this.aigisSessions.get(sessionId); this.aigisSessions.delete(sessionId);
    if (!pending || pending.mobile !== mobile || pending.expires < Date.now()
      || verificationFromAigis(pending.session).challenge !== challenge) {
      throw new AppError("aigis_session_missing", "验证码验证会话不存在或已过期", 404);
    }
    const session = await this.createMobileCaptchaWithAigis(mobile, createAigisHeader(sessionId, challenge, validate));
    return session;
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
      this.aigisSessions.set(aigisSession.session_id, { session: aigisSession, mobile, expires: Date.now() + 5 * 60_000 });
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
  getPredownloadBuild(installedVersion?: string, audioLanguages?: string[]): Promise<GameBuild | null> { return this.sophon.predownloadBuild(installedVersion, audioLanguages); }

  async *wishes(credential: string, role: GameRole, newest: Record<string, string>): AsyncIterable<WishRecord[]> {
    let authkey = "";
    try { authkey = await this.authkey(credential, role); } catch (error) { normalizeWishSyncError(error); }
    for (const type of ["100", "200", "301", "302", "500"]) {
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

  getDailyNote(credential: string, role: GameRole, challenge = "", challengePath = ""): Promise<DailyNote> {
    return getLiveDailyNote(credential, role, this.device, challenge, challengePath);
  }

  verifyNoteChallenge(credential: string, challenge: string, validate: string, challengePath = ""): Promise<string> {
    return verifyLiveNoteChallenge(credential, this.device, challenge, validate, challengePath);
  }

  async createAuthTicket(credential: string): Promise<string> {
    const map = cookies(credential), stoken = map.get("stoken") ?? "", mid = map.get("mid") ?? "", aid = map.get("stuid") ?? map.get("account_id") ?? "";
    if (!stoken || !mid || !aid) throw new AppError("credential_invalid", "Cookie 缺少 stoken/mid/stuid，无法创建游戏登录票据", 422);
    const body = JSON.stringify({ game_biz: "hk4e_cn", mid, stoken, uid: Number(aid) });
    const data = await this.request("https://passport-api.mihoyo.com/account/ma-cn-verifier/app/createAuthTicketByGameBiz", {
      method: "POST", headers: { Cookie: credential, "User-Agent": "HYPContainer/1.1.4.133", "x-rpc-app_id": "ddxf5dufpuyo", "x-rpc-client_type": "3", "x-rpc-device_id": this.device.loginDeviceId, "Content-Type": "application/json" }, body,
    });
    return String((data as JSONValue).ticket ?? "");
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
    map.set("stuid", uid); map.set("stoken", String(stoken));
    map.delete("login_ticket"); map.delete("login_uid");
    return this.serialize(map);
  }
  private async enrichCredential(value: string, cookieImport = false): Promise<string> {
    try {
      return await completeCredential(value, this.device.deviceId);
    } catch (error) {
      if (cookieImport && error instanceof AppError && error.code === "mihoyo_error") throw new AppError("credential_expired", "米游社返回登录状态失效，请重新获取 Cookie 后重试", 401, error.details);
      throw error;
    }
  }
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
