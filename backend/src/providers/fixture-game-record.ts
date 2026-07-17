import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { GameCharacter, GameRole, WishRecord } from "../core/models";
import type { GachaUrlProof, GameRecordSource } from "./game-record";

export class FixtureGameRecordSource implements GameRecordSource {
  constructor(private readonly root: string) {}

  async characters(_credential: string, role: GameRole): Promise<GameCharacter[]> {
    const now = new Date().toISOString();
    return [
      this.character(role.uid, "10000089", "芙宁娜", "Water", 90, 5, 2, "静水流涌之辉", now),
      this.character(role.uid, "10000075", "流浪者", "Wind", 90, 5, 0, "图莱杜拉的回忆", now),
    ];
  }

  async characterDetail(credential: string, role: GameRole, avatarId: string): Promise<GameCharacter> {
    return (await this.characters(credential, role)).find((item) => item.avatar_id === avatarId)
      ?? this.character(role.uid, avatarId, "旅行者", "None", 90, 5, 0, "无锋剑", new Date().toISOString());
  }

  async verifyGachaUrl(url: string): Promise<GachaUrlProof> {
    const uid = new URL(url).searchParams.get("uid") ?? "100000001";
    const records = this.json<WishRecord[]>("wishes.json").map((value) => ({ ...value, uid }));
    return { uid, records: records.slice(0, 20) };
  }

  async *wishesFromGachaUrl(url: string): AsyncIterable<WishRecord[]> {
    const uid = new URL(url).searchParams.get("uid") ?? "100000001";
    yield this.json<WishRecord[]>("wishes.json").map((value) => ({
      ...value, uid, uigf_gacha_type: value.uigf_gacha_type || (value.gacha_type === "400" ? "301" : value.gacha_type),
    }));
  }

  private character(uid: string, avatarId: string, name: string, element: string, level: number, rarity: number, constellation: number, weapon: string, updatedAt: string): GameCharacter {
    return { uid, avatar_id: avatarId, name, element, level, rarity, constellation, fetter: 10, weapon_name: weapon, weapon_level: 90, icon_url: null, updated_at: updatedAt, payload: { avatar_id: avatarId, weapon: { name: weapon, level: 90 } } };
  }

  private json<T>(name: string): T {
    return JSON.parse(readFileSync(join(this.root, name), "utf8")) as T;
  }
}
