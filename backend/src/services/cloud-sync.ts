import { writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Settings } from "../core/config";
import type { Store } from "../core/database";
import { AppError } from "../core/errors";
import type { CloudLoginResult, GameRole } from "../core/models";
import type { Provider } from "../providers/provider";
import type { WishService } from "./wishes";
import type { AchievementService } from "./achievements";
import { z } from "zod";

const cloudWish = z.object({
  id: z.string().regex(/^\d{1,19}$/), uid: z.string().regex(/^\d{9,10}$/),
  gacha_type: z.enum(["100", "200", "301", "302", "400", "500"]),
  uigf_gacha_type: z.enum(["100", "200", "301", "302", "500"]), item_id: z.string().regex(/^(?:|\d{1,19})$/),
  name: z.string().max(128), item_type: z.string().max(64), rank: z.number().int().min(1).max(5),
  time: z.string().datetime(),
}).strict();
const cloudAchievement = z.object({
  achievement_id: z.number().int().positive(), current: z.number().int().min(0),
  status: z.number().int().min(0).max(3), timestamp: z.number().int().min(0),
}).strict();

const forwardedCloudErrors = new Set([
  "gacha_url_invalid", "gacha_url_expired", "gacha_url_unverified", "gacha_item_invalid",
  "identity_mismatch", "reverify_required", "unauthorized",
  "achievement_items_invalid", "stored_data_invalid",
]);

export class CloudSyncService {
  constructor(
    private readonly settings: Settings,
    private readonly store: Store,
    private readonly provider: Provider,
    private readonly wishes: WishService,
    private readonly achievements: AchievementService,
  ) {}

  async loginWithCredential(credential: string, role: GameRole): Promise<CloudLoginResult> {
    return this.login(await this.provider.gachaUrl(credential, role), role.uid);
  }

  async login(gachaUrl: string, expectedUid = ""): Promise<CloudLoginResult> {
    const value = await this.remote<CloudLoginResult>("/api/v1/auth/gacha-url", "", { gacha_url: gachaUrl });
    this.assertExpectedUid(value.uid, expectedUid);
    this.save(value.uid, value.token_ref, value.reverified_at);
    return value;
  }

  async reverify(gachaUrl: string, token: string): Promise<CloudLoginResult> {
    const value = await this.remote<CloudLoginResult>("/api/v1/auth/reverify", token, { gacha_url: gachaUrl });
    this.save(value.uid, value.token_ref, value.reverified_at);
    return value;
  }

  session(uid: string): Record<string, unknown> | null {
    return this.store.one("SELECT * FROM cloud_sessions WHERE uid=?", uid) ?? null;
  }

  async uploadWishes(uid: string, token: string): Promise<Record<string, number>> {
    const items = this.wishes.list(uid).map(({ id, uid: itemUid, gacha_type, uigf_gacha_type, item_id, name, item_type, rank, time }) => (
      { id, uid: itemUid, gacha_type, uigf_gacha_type, item_id, name, item_type, rank, time }
    ));
    await this.assertRemoteIdentity(uid, token);
    return this.remote<Record<string, number>>("/api/v1/gacha/upload", token, { items });
  }

  async retrieveWishes(uid: string, token: string): Promise<Record<string, number>> {
    await this.assertRemoteIdentity(uid, token);
    const payload = await this.remote<{ items: unknown[] }>("/api/v1/gacha/retrieve", token, {});
    const items = z.array(cloudWish).max(20_000).safeParse(payload.items);
    if (!items.success) throw new AppError("cloud_payload_invalid", "云端记录格式无效", 502);
    this.wishes.save(items.data);
    return { imported: items.data.length };
  }

  async uploadAchievements(uid: string, token: string): Promise<Record<string, number>> {
    const items = this.achievements.list(uid).map(({ achievement_id, current, status, timestamp }) => (
      { achievement_id, current, status, timestamp }
    ));
    await this.assertRemoteIdentity(uid, token);
    return this.remote<Record<string, number>>("/api/v1/achievements/upload", token, { items });
  }

  async retrieveAchievements(uid: string, token: string): Promise<Record<string, number>> {
    await this.assertRemoteIdentity(uid, token);
    const payload = await this.remote<{ items: unknown[] }>("/api/v1/achievements/retrieve", token, {});
    const items = z.array(cloudAchievement).max(200_000).safeParse(payload.items);
    if (!items.success) throw new AppError("cloud_payload_invalid", "云端成就格式无效", 502);
    const archive = this.achievements.archiveForUid(uid);
    const revision = this.achievements.snapshot(archive.id).revision;
    this.achievements.importUIAF(archive.id, revision, {
      list: items.data.map(({ achievement_id, ...item }) => ({ id: achievement_id, ...item })),
    });
    return { imported: items.data.length };
  }

  async deleteWishes(uid: string, token: string): Promise<Record<string, number>> {
    await this.assertRemoteIdentity(uid, token);
    return this.remote<Record<string, number>>("/api/v1/gacha", token, undefined, "DELETE");
  }

  async revokeSession(uid: string, token: string): Promise<void> {
    await this.assertRemoteIdentity(uid, token);
    await this.remote<Record<string, never>>("/api/v1/auth/revoke", token, {});
    this.store.db.prepare("DELETE FROM cloud_sessions WHERE uid=?").run(uid);
  }

  private save(uid: string, tokenRef: string, reverifiedAt: string): void {
    const now = new Date().toISOString();
    this.store.db.prepare(`INSERT INTO cloud_sessions(uid,token_ref,reverified_at,updated_at) VALUES(?,?,?,?)
      ON CONFLICT(uid) DO UPDATE SET token_ref=excluded.token_ref,reverified_at=excluded.reverified_at,updated_at=excluded.updated_at`)
      .run(uid, tokenRef, reverifiedAt, now);
  }

  private async remote<T>(path: string, token: string, body?: unknown, method = "POST"): Promise<T> {
    const baseUrl = this.settings.cloudBaseUrl?.trim() ?? "";
    if (!baseUrl) throw new AppError("cloud_not_configured", "云同步服务尚未配置", 503);
    let response: Response;
    try {
      response = await fetch(`${baseUrl}${path}`, {
        method, headers: { "Content-Type": "application/json", Authorization: token ? `Bearer ${token}` : "" },
        body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(30_000),
      });
    } catch {
	    this.recordFailure(path, 503, "cloud_error");
      throw new AppError("cloud_error", "云同步服务暂不可用", 503);
    }
    const payload = response.status === 204 ? {} as T & { code?: string; message?: string }
      : await response.json() as T & { code?: string; message?: string };
    if (!response.ok) {
      const code = payload.code && forwardedCloudErrors.has(payload.code) ? payload.code : "cloud_error";
	    this.recordFailure(path, response.status, code, payload.code);
      throw new AppError(code, payload.message ?? "云端服务请求失败", response.status);
    }
    return payload;
  }

  private async assertRemoteIdentity(uid: string, token: string): Promise<void> {
    const session = await this.remote<{ uid: string }>("/api/v1/me", token, undefined, "GET");
    if (session.uid !== uid) throw new AppError("cloud_identity_mismatch", "云端会话与角色 UID 不匹配", 403);
  }

  private assertExpectedUid(uid: string, expectedUid: string): void {
    if (expectedUid && uid !== expectedUid) throw new AppError("cloud_identity_mismatch", "云端鉴权 UID 与当前角色不匹配", 403);
  }

	private recordFailure(path: string, status: number, code: string, upstreamCode?: string): void {
	  try {
	    writeFileSync(join(this.settings.dataDir, "cloud-sync-diagnostic.json"), JSON.stringify({
	      timestamp: new Date().toISOString(), path, status, code, upstream_code: upstreamCode ?? null,
	    }), { encoding: "utf8", mode: 0o600 });
	  } catch { /* 诊断写入失败不能覆盖原始云端错误。 */ }
	}
}
