import type { DailyNote, GameRole } from "../core/models";
import type { Store } from "../core/database";
import type { Provider } from "../providers/provider";

export class NoteService {
  constructor(private readonly store: Store, private readonly provider: Provider) {}

  async refresh(credential: string, role: GameRole, challenge = ""): Promise<DailyNote> {
    const note = await this.provider.getDailyNote(credential, role, challenge);
    this.store.db.prepare(`INSERT INTO notes(uid,payload,refreshed_at) VALUES(?,?,?)
      ON CONFLICT(uid) DO UPDATE SET payload=excluded.payload,refreshed_at=excluded.refreshed_at`)
      .run(role.uid, JSON.stringify(note), note.refreshed_at);
    return note;
  }

  verify(credential: string, challenge: string, validate: string): Promise<string> {
    return this.provider.verifyNoteChallenge(credential, challenge, validate);
  }

  get(uid: string): DailyNote | null {
    const row = this.store.one("SELECT payload FROM notes WHERE uid=?", uid);
    return row ? JSON.parse(String(row.payload)) as DailyNote : null;
  }
}
