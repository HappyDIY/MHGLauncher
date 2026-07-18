import { AppError } from "../core/errors";
import type { Store } from "../core/database";
import type { AchievementArchive, AchievementGoal, AchievementItem, AchievementSnapshot, AchievementViewItem } from "../core/models";
import type { AchievementMetadata } from "./achievement-metadata";
import type { AchievementResources } from "./achievement-resources";

type UIAF = { info?: Record<string, unknown>; list?: { id: number; current?: number; status?: number; timestamp?: number }[] };

const archive = (row: Record<string, unknown>): AchievementArchive => ({
  id: String(row.id), name: String(row.name), selected: Boolean(row.selected),
  created_at: String(row.created_at), updated_at: String(row.updated_at), revision: Number(row.revision ?? 0),
});
const item = (row: Record<string, unknown>): AchievementItem => ({
  archive_id: String(row.archive_id), achievement_id: Number(row.achievement_id),
  current: Number(row.current), status: Number(row.status), timestamp: Number(row.timestamp),
  updated_at: String(row.updated_at),
});
export class AchievementService {
  constructor(private readonly store: Store, private readonly resources: AchievementResources) {}

  archiveForUid(uid: string): AchievementArchive {
    if (!/^\d{9,10}$/.test(uid)) throw new AppError("uid_invalid", "角色 UID 无效", 422);
    const now = new Date().toISOString();
    this.store.db.transaction(() => {
      this.store.db.exec("UPDATE achievement_archives SET selected=0");
      this.store.db.prepare(`INSERT INTO achievement_archives(id,name,selected,created_at,updated_at,revision)
        VALUES(?,?,1,?,?,0) ON CONFLICT(id) DO UPDATE SET name=excluded.name,selected=1`)
        .run(uid, uid, now, now);
    })();
    return archive(this.store.one("SELECT * FROM achievement_archives WHERE id=?", uid)!);
  }

  list(archiveId: string): AchievementItem[] {
    return this.store.all("SELECT * FROM achievements WHERE archive_id=? ORDER BY achievement_id", archiveId).map(item);
  }

  async goals(): Promise<AchievementGoal[]> {
    return (await this.resources.metadata()).goals.map((value) => ({
      id: value.Id, order: value.Order, name: value.Name,
      reward_count: value.FinishReward?.Count ?? 0, icon_url: this.resources.iconUrl(value.Icon),
    }));
  }

  async view(archiveId: string): Promise<AchievementViewItem[]> {
    const existing = new Map(this.list(archiveId).map((value) => [value.achievement_id, value]));
    return (await this.resources.metadata()).achievements.map((meta) => {
      const saved = existing.get(meta.Id);
      return {
        archive_id: archiveId ?? "", achievement_id: meta.Id, current: saved?.current ?? 0,
        status: saved?.status ?? 0, timestamp: saved?.timestamp ?? 0, updated_at: saved?.updated_at ?? "",
        goal: meta.Goal, order: meta.Order, title: meta.Title, description: meta.Description,
        progress: meta.Progress, version: meta.Version, reward_count: meta.FinishReward?.Count ?? 0,
        icon_url: this.resources.iconUrl(meta.Icon), is_daily_quest: Boolean(meta.IsDailyQuest),
      };
    });
  }

  async snapshot(archiveId: string): Promise<AchievementSnapshot> {
    const row = this.store.one("SELECT * FROM achievement_archives WHERE id=?", archiveId);
    if (!row) throw new AppError("archive_missing", "成就档案不存在", 404);
    const selected = archive(row);
    return { archive: selected, entries: await this.view(archiveId), revision: selected.revision ?? 0 };
  }

  async saveSnapshot(
    archiveId: string, expectedRevision: number,
    values: Omit<AchievementItem, "archive_id" | "updated_at">[],
  ): Promise<AchievementSnapshot> {
    const metadata = (await this.resources.metadata()).achievements;
    this.store.db.transaction(() => {
      const current = Number(this.store.one("SELECT revision FROM achievement_archives WHERE id=?", archiveId)?.revision ?? -1);
      if (current < 0) throw new AppError("archive_missing", "成就档案不存在", 404);
      if (current !== expectedRevision) throw new AppError("archive_revision_conflict", "成就档案已被其他操作更新", 409);
      this.writeItems(archiveId, values, metadata);
      this.store.db.prepare("UPDATE achievement_archives SET revision=revision+1,updated_at=? WHERE id=?")
        .run(new Date().toISOString(), archiveId);
    })();
    return await this.snapshot(archiveId);
  }

  async save(archiveId: string, values: Omit<AchievementItem, "archive_id" | "updated_at">[]): Promise<AchievementItem[]> {
    this.requireArchive(archiveId);
    const metadata = (await this.resources.metadata()).achievements;
    this.store.db.transaction(() => this.writeItems(archiveId, values, metadata))();
    return this.list(archiveId);
  }

  private writeItems(
    archiveId: string,
    values: Omit<AchievementItem, "archive_id" | "updated_at">[],
    metadata: AchievementMetadata[],
  ): void {
    const now = new Date().toISOString();
    const insert = this.store.db.prepare(`INSERT INTO achievements(archive_id,achievement_id,current,status,timestamp,updated_at)
      VALUES(?,?,?,?,?,?) ON CONFLICT(archive_id,achievement_id) DO UPDATE SET
      current=excluded.current,status=excluded.status,timestamp=excluded.timestamp,updated_at=excluded.updated_at`);
    const progress = new Map(metadata.map((value) => [value.Id, value.Progress]));
    values.forEach((value) => {
      const current = value.status >= 2 ? Math.max(value.current, progress.get(value.achievement_id) ?? 0) : value.current;
      insert.run(archiveId, value.achievement_id, current, value.status, value.timestamp, now);
    });
  }

  async importUIAF(archiveId: string, expectedRevision: number, payload: UIAF): Promise<AchievementSnapshot> {
    const values = (payload.list ?? []).map((value) => ({
      achievement_id: Number(value.id), current: Number(value.current ?? 0),
      status: Number(value.status ?? 0), timestamp: Number(value.timestamp ?? 0),
    })).filter((value) => value.achievement_id > 0);
    return await this.saveSnapshot(archiveId, expectedRevision, values);
  }

  exportUIAF(archiveId: string): Record<string, unknown> {
    return { info: { export_app: "MHGLauncher", uiaf_version: "v1.1", export_timestamp: Math.floor(Date.now() / 1000) },
      list: this.list(archiveId).map((value) => ({ id: value.achievement_id, current: value.current, status: value.status, timestamp: value.timestamp })) };
  }

  private requireArchive(id: string): void {
    if (!this.store.one("SELECT id FROM achievement_archives WHERE id=?", id)) throw new AppError("archive_missing", "成就档案不存在", 404);
  }
}
