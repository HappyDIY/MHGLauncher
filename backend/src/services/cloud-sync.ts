import { randomBytes } from "node:crypto";
import type { Settings } from "../core/config";
import type { Store } from "../core/database";
import { AppError } from "../core/errors";
import type { CloudLoginResult } from "../core/models";
import type { GameRecordSource } from "../providers/game-record";
import type { WishService } from "./wishes";

export class CloudSyncService {
  constructor(
    private readonly settings: Settings,
    private readonly store: Store,
    private readonly records: GameRecordSource,
    private readonly wishes: WishService,
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
    await this.assertRemoteIdentity(uid, token);
    return this.remote<Record<string, number>>("/api/v1/gacha/upload", token, { items });
  }

  async retrieveWishes(uid: string, token: string): Promise<Record<string, number>> {
    if (!this.settings.cloudBaseUrl) return { imported: 0 };
    await this.assertRemoteIdentity(uid, token);
    const items = await this.remote<{ items: unknown[] }>("/api/v1/gacha/retrieve", token, {});
    this.wishes.save(items.items as Parameters<WishService["save"]>[0]);
    return { imported: items.items.length };
  }

  async deleteWishes(uid: string, token: string): Promise<Record<string, number>> {
    if (!this.settings.cloudBaseUrl) return { deleted: 0 };
    await this.assertRemoteIdentity(uid, token);
    return this.remote<Record<string, number>>("/api/v1/gacha", token, undefined, "DELETE");
  }

  async revokeSession(uid: string, token: string): Promise<void> {
    if (this.settings.cloudBaseUrl) {
      await this.assertRemoteIdentity(uid, token);
      await this.remote<Record<string, never>>("/api/v1/auth/revoke", token, {});
    }
    this.store.db.prepare("DELETE FROM cloud_sessions WHERE uid=?").run(uid);
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
    const payload = response.status === 204 ? {} as T & { message?: string } : await response.json() as T & { message?: string };
    if (!response.ok) throw new AppError("cloud_error", payload.message ?? "云端服务请求失败", response.status);
    return payload;
  }

  private async assertRemoteIdentity(uid: string, token: string): Promise<void> {
    const session = await this.remote<{ uid: string }>("/api/v1/me", token, undefined, "GET");
    if (session.uid !== uid) throw new AppError("cloud_identity_mismatch", "云端会话与角色 UID 不匹配", 403);
  }

  private token(): string { return randomBytes(32).toString("base64url"); }
}
