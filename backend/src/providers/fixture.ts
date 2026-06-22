import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { AccountIdentity, DailyNote, GameRole, QRSession, WishRecord } from "../core/models";
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

  async getRoles(_credential: string): Promise<GameRole[]> {
    return [{ uid: "100000001", nickname: "旅行者", region: "cn_gf01", level: 60, selected: false }];
  }

  async getBuild(_installedVersion = ""): Promise<GameBuild> {
    return normalizeBuild(this.json<Partial<GameBuild> & Pick<GameBuild, "version">>("build.json"));
  }

  async *wishes(_credential: string, _role: GameRole, _newest: Record<string, string>): AsyncIterable<WishRecord[]> {
    yield this.json<WishRecord[]>("wishes.json");
  }

  async getDailyNote(_credential: string, role: GameRole, _challenge = ""): Promise<DailyNote> {
    return { uid: role.uid, ...this.json<Omit<DailyNote, "uid">>("note.json") };
  }

  async verifyNoteChallenge(_credential: string, _challenge: string, _validate: string): Promise<string> {
    return "fixture-xrpc-challenge";
  }

  private session(id: string, status: QRSession["status"]): QRSession {
    return { id, url: "https://example.invalid/fixture-login", status, expires_at: new Date(Date.now() + 300_000).toISOString() };
  }

  private json<T>(name: string): T {
    return JSON.parse(readFileSync(join(this.root, name), "utf8")) as T;
  }
}
