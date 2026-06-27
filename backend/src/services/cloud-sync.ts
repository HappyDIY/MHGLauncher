import { randomBytes } from "node:crypto";
import type { Settings } from "../core/config";
import type { Store } from "../core/database";
import { AppError } from "../core/errors";
import type { CloudLoginResult, CycleKind } from "../core/models";
import type { GameRecordSource } from "../providers/game-record";
import type { CycleService } from "./cycles";
import type { WishService } from "./wishes";

export class CloudSyncService {
  constructor(
    private readonly settings: Settings,
    private readonly store: Store,
    private readonly records: GameRecordSource,
    private readonly wishes: WishService,
    private readonly cycles: CycleService,
  ) {}

  async login(gachaUrl: string): Promise<CloudLoginResult> {
    if (this.settings.cloudBaseUrl) {
      const value = await this.remote<CloudLoginResult>("/api/v1/auth/gacha-url", "", { gacha_url: gachaUrl });
      this.save(value.uid, value.token_ref, value.reverified_at);
      return value;
    }
    const proof = await this.records.verifyGachaUrl(gachaUrl);
    const result = { uid: proof.uid, token: this.token(), token_ref: `keychain:cloud:${proof.uid}`, reverified_at: new Date().toISOString() };
    this.save(result.uid, result.token_ref, result.reverified_at);
    return result;
  }

  async reverify(gachaUrl: string, token: string): Promise<CloudLoginResult> {
    if (this.settings.cloudBaseUrl) {
      const value = await this.remote<CloudLoginResult>("/api/v1/auth/reverify", token, { gacha_url: gachaUrl });
      this.save(value.uid, value.token_ref, value.reverified_at);
      return value;
    }
    const proof = await this.records.verifyGachaUrl(gachaUrl);
    const result = { uid: proof.uid, token, token_ref: `keychain:cloud:${proof.uid}`, reverified_at: new Date().toISOString() };
    this.save(result.uid, result.token_ref, result.reverified_at);
    return result;
  }

  session(uid: string): Record<string, unknown> | null {
    return this.store.one("SELECT * FROM cloud_sessions WHERE uid=?", uid) ?? null;
  }

  async uploadWishes(uid: string, token: string): Promise<Record<string, number>> {
    const items = this.wishes.list(uid);
    if (!this.settings.cloudBaseUrl) return { uploaded: items.length };
    return this.remote<Record<string, number>>("/api/v1/gacha/upload", token, { uid, items });
  }

  async retrieveWishes(uid: string, token: string): Promise<Record<string, number>> {
    if (!this.settings.cloudBaseUrl) return { imported: 0 };
    const items = await this.remote<{ items: unknown[] }>("/api/v1/gacha/retrieve", token, { uid });
    this.wishes.save(items.items as Parameters<WishService["save"]>[0]);
    return { imported: items.items.length };
  }

  async deleteWishes(uid: string, token: string): Promise<Record<string, number>> {
    if (!this.settings.cloudBaseUrl) return { deleted: 0 };
    return this.remote<Record<string, number>>(`/api/v1/gacha/${encodeURIComponent(uid)}`, token, undefined, "DELETE");
  }

  async uploadCycle(uid: string, kind: CycleKind, scheduleId: string, token: string): Promise<Record<string, number>> {
    const record = this.cycles.list(uid, kind).find((value) => value.schedule_id === scheduleId);
    if (!record) throw new AppError("cycle_record_missing", "周期记录不存在", 404);
    if (this.settings.cloudBaseUrl) await this.remote(`/api/v1/cycles/${kind}/upload`, token, { record });
    this.cycles.markUploaded(uid, kind, scheduleId);
    return { uploaded: 1 };
  }

  private save(uid: string, tokenRef: string, reverifiedAt: string): void {
    const now = new Date().toISOString();
    this.store.db.prepare(`INSERT INTO cloud_sessions(uid,token_ref,reverified_at,updated_at) VALUES(?,?,?,?)
      ON CONFLICT(uid) DO UPDATE SET token_ref=excluded.token_ref,reverified_at=excluded.reverified_at,updated_at=excluded.updated_at`)
      .run(uid, tokenRef, reverifiedAt, now);
  }

  private async remote<T>(path: string, token: string, body?: unknown, method = "POST"): Promise<T> {
    const response = await fetch(`${this.settings.cloudBaseUrl}${path}`, {
      method, headers: { "Content-Type": "application/json", Authorization: token ? `Bearer ${token}` : "" },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(30_000),
    });
    const payload = await response.json() as T & { message?: string };
    if (!response.ok) throw new AppError("cloud_error", payload.message ?? "云端服务请求失败", response.status);
    return payload;
  }

  private token(): string { return randomBytes(32).toString("base64url"); }
}
