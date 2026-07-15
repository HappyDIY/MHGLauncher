import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { AccountIdentity, DailyNote, GameRole, MobileCaptchaSession, QRSession, WishRecord } from "../core/models";
import type { GameBuild, Provider } from "./provider";
import { normalizeBuild } from "./provider";

export class FixtureProvider implements Provider {
  private readonly polls = new Map<string, number>();
  constructor(private readonly root: string) {}

  async createQRSession(): Promise<QRSession> {
    const session = this.session("fixture-ticket", "created");
    this.polls.set(session.id, 0);
    return session;
  }

  async queryQRSession(id: string): Promise<[QRSession, AccountIdentity | null]> {
    const count = (this.polls.get(id) ?? 0) + 1;
    this.polls.set(id, count);
    const session = this.session(id, count >= 2 ? "confirmed" : "scanned");
    const identity = count < 2 ? null : {
      aid: "10001", mid: "fixture-mid", nickname: "测试旅行者",
      credential: "stoken=fixture; mid=fixture-mid",
    };
    return [session, identity];
  }

  async identifyCredential(credential: string): Promise<AccountIdentity> {
    const aid = /(?:^|;\s*)(?:stuid|account_id)=([^;]+)/.exec(credential)?.[1] ?? "10001";
    const mid = /(?:^|;\s*)mid=([^;]+)/.exec(credential)?.[1] ?? `fixture-mid-${aid}`;
    return { aid, mid, nickname: "测试旅行者", credential };
  }

  async createMobileCaptcha(mobile: string): Promise<MobileCaptchaSession> {
    return { mobile, action_type: "fixture-action", countdown: 60, aigis: null };
  }

  async verifyMobileCaptcha(mobile: string, _sessionId: string, _challenge: string, _validate: string): Promise<MobileCaptchaSession> {
    return { mobile, action_type: "fixture-action", countdown: 60, aigis: "fixture-aigis" };
  }

  async loginByMobileCaptcha(mobile: string, _captcha: string, _actionType: string, _aigis?: string | null): Promise<AccountIdentity> {
    return { aid: "10001", mid: "fixture-mid", nickname: `手机用户${mobile.slice(-4)}`, credential: "stoken=fixture; mid=fixture-mid" };
  }

  async getRoles(_credential: string): Promise<GameRole[]> {
    return [{ uid: "100000001", nickname: "旅行者", region: "cn_gf01", level: 60, selected: false }];
  }

  async getBuild(_installedVersion = "", _audioLanguages?: string[]): Promise<GameBuild> {
    return normalizeBuild(this.json<Partial<GameBuild> & Pick<GameBuild, "version">>("build.json"));
  }

  async getInstalledBuild(installedVersion: string, _audioLanguages?: string[]): Promise<GameBuild> {
    try { return normalizeBuild(this.json<Partial<GameBuild> & Pick<GameBuild, "version">>("installed.json")); }
    catch { return { ...await this.getBuild(), version: installedVersion }; }
  }

  async getPredownloadBuild(_installedVersion?: string, _audioLanguages?: string[]): Promise<GameBuild | null> {
    try { return normalizeBuild(this.json<Partial<GameBuild> & Pick<GameBuild, "version">>("predownload.json")); }
    catch { return null; }
  }

  async *wishes(_credential: string, _role: GameRole, _newest: Record<string, string>): AsyncIterable<WishRecord[]> {
    yield this.json<WishRecord[]>("wishes.json").map((value) => ({
      ...value, uigf_gacha_type: value.uigf_gacha_type || (value.gacha_type === "400" ? "301" : value.gacha_type),
      time: value.time.replace(" ", "T"),
    }));
  }

  async getDailyNote(_credential: string, role: GameRole, _challenge = "", _challengePath = ""): Promise<DailyNote> {
    return { uid: role.uid, ...this.json<Omit<DailyNote, "uid">>("note.json") };
  }

  async verifyNoteChallenge(_credential: string, _challenge: string, _validate: string, _challengePath = ""): Promise<string> {
    return "fixture-xrpc-challenge";
  }

  async createAuthTicket(_credential: string): Promise<string> {
    return "fixture-auth-ticket";
  }

  private session(id: string, status: QRSession["status"]): QRSession {
    return { id, url: "https://example.invalid/fixture-login", status, expires_at: new Date(Date.now() + 300_000).toISOString() };
  }

  private json<T>(name: string): T {
    return JSON.parse(readFileSync(join(this.root, name), "utf8")) as T;
  }
}
