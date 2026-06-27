import { AppError } from "../core/errors";
import type { Store } from "../core/database";
import type { CycleKind, CycleRecord, GameRole } from "../core/models";
import type { GameRecordSource } from "../providers/game-record";

const kinds = new Set<CycleKind>(["abyss", "theatre", "hard"]);
const record = (row: Record<string, unknown>): CycleRecord => ({
  uid: String(row.uid), kind: row.kind as CycleKind, schedule_id: String(row.schedule_id),
  title: String(row.title), summary: String(row.summary),
  started_at: row.started_at ? String(row.started_at) : null,
  ended_at: row.ended_at ? String(row.ended_at) : null,
  uploaded_at: row.uploaded_at ? String(row.uploaded_at) : null,
  payload: JSON.parse(String(row.payload)), updated_at: String(row.updated_at),
});

export class CycleService {
  constructor(private readonly store: Store, private readonly records: GameRecordSource) {}

  list(uid: string, kind: CycleKind): CycleRecord[] {
    this.ensure(kind);
    return this.store.all("SELECT * FROM cycle_records WHERE uid=? AND kind=? ORDER BY schedule_id DESC", uid, kind).map(record);
  }

  async refresh(credential: string, role: GameRole, kind: CycleKind): Promise<CycleRecord[]> {
    this.ensure(kind);
    const values = await this.records.cycles(credential, role, kind);
    this.save(values);
    return values;
  }

  markUploaded(uid: string, kind: CycleKind, scheduleId: string): void {
    this.store.db.prepare("UPDATE cycle_records SET uploaded_at=? WHERE uid=? AND kind=? AND schedule_id=?")
      .run(new Date().toISOString(), uid, kind, scheduleId);
  }

  private save(values: CycleRecord[]): void {
    const insert = this.store.db.prepare(`INSERT INTO cycle_records(uid,kind,schedule_id,title,summary,started_at,ended_at,uploaded_at,payload,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(uid,kind,schedule_id) DO UPDATE SET
      title=excluded.title,summary=excluded.summary,started_at=excluded.started_at,ended_at=excluded.ended_at,
      payload=excluded.payload,updated_at=excluded.updated_at`);
    this.store.db.transaction(() => values.forEach((value) => insert.run(
      value.uid, value.kind, value.schedule_id, value.title, value.summary, value.started_at,
      value.ended_at, value.uploaded_at, JSON.stringify(value.payload), value.updated_at,
    )))();
  }

  private ensure(kind: CycleKind): void {
    if (!kinds.has(kind)) throw new AppError("cycle_kind_invalid", "周期类型无效", 422);
  }
}
