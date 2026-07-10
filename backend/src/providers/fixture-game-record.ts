import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { GameCharacter, GameRole, GachaEvent, WishRecord } from "../core/models";
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

  async gachaEvents(_credential: string, _role: GameRole): Promise<GachaEvent[]> {
    const now = new Date().toISOString();
    return [
      this.event("fixture-301", "5.7", "301", "角色活动祈愿", ["丝柯克"], ["班尼特", "坎蒂丝", "夏沃蕾"], now),
      this.event("fixture-302", "5.7", "302", "武器活动祈愿", ["苍耀", "裁断"], ["祭礼剑", "西风猎弓"], now),
    ];
  }

  async verifyGachaUrl(url: string): Promise<GachaUrlProof> {
    const uid = new URL(url).searchParams.get("uid") ?? "100000001";
    const records = this.json<WishRecord[]>("wishes.json").map((value) => ({ ...value, uid }));
    return { uid, records: records.slice(0, 20) };
  }

  private character(uid: string, avatarId: string, name: string, element: string, level: number, rarity: number, constellation: number, weapon: string, updatedAt: string): GameCharacter {
    return { uid, avatar_id: avatarId, name, element, level, rarity, constellation, fetter: 10, weapon_name: weapon, weapon_level: 90, icon_url: null, updated_at: updatedAt, payload: { avatar_id: avatarId, weapon: { name: weapon, level: 90 } } };
  }

  private event(id: string, version: string, type: string, name: string, orange: string[], purple: string[], updatedAt: string): GachaEvent {
    return { id, version, gacha_type: type, name, started_at: "2026-06-18T18:00:00+08:00", ended_at: "2026-07-08T14:59:59+08:00", orange_up: orange, purple_up: purple, banner_url: null, updated_at: updatedAt };
  }

  private json<T>(name: string): T {
    return JSON.parse(readFileSync(join(this.root, name), "utf8")) as T;
  }
}
