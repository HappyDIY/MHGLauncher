import type { Store } from "../core/database";
import type { GameCharacter, GameRole } from "../core/models";
import type { GameRecordSource } from "../providers/game-record";

const row = (value: Record<string, unknown>): GameCharacter => ({
  uid: String(value.uid), avatar_id: String(value.avatar_id), name: String(value.name),
  element: String(value.element), level: Number(value.level), rarity: Number(value.rarity),
  constellation: Number(value.constellation), fetter: Number(value.fetter),
  weapon_name: String(value.weapon_name), weapon_level: Number(value.weapon_level),
  icon_url: value.icon_url ? String(value.icon_url) : null,
  payload: JSON.parse(String(value.payload)), updated_at: String(value.updated_at),
});

export class CharacterService {
  constructor(private readonly store: Store, private readonly records: GameRecordSource) {}

  list(uid: string): GameCharacter[] {
    return this.store.all("SELECT * FROM characters WHERE uid=? ORDER BY rarity DESC,level DESC,name", uid).map(row);
  }

  async refresh(credential: string, role: GameRole): Promise<GameCharacter[]> {
    const values = await this.records.characters(credential, role);
    this.save(values);
    return values;
  }

  async refreshDetail(credential: string, role: GameRole, avatarId: string): Promise<GameCharacter> {
    const value = await this.records.characterDetail(credential, role, avatarId);
    this.save([value]);
    return value;
  }

  private save(values: GameCharacter[]): void {
    const insert = this.store.db.prepare(`INSERT INTO characters(uid,avatar_id,name,element,level,rarity,constellation,fetter,weapon_name,weapon_level,icon_url,payload,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(uid,avatar_id) DO UPDATE SET
      name=excluded.name,element=excluded.element,level=excluded.level,rarity=excluded.rarity,
      constellation=excluded.constellation,fetter=excluded.fetter,weapon_name=excluded.weapon_name,
      weapon_level=excluded.weapon_level,icon_url=excluded.icon_url,payload=excluded.payload,updated_at=excluded.updated_at`);
    this.store.db.transaction(() => values.forEach((value) => insert.run(
      value.uid, value.avatar_id, value.name, value.element, value.level, value.rarity,
      value.constellation, value.fetter, value.weapon_name, value.weapon_level,
      value.icon_url ?? null, JSON.stringify(value.payload), value.updated_at,
    )))();
  }
}
