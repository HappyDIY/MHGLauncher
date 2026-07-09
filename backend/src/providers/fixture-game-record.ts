import type { GameCharacter, GameRole } from "../core/models";
import type { GameRecordSource } from "./game-record";

type JSONValue = Record<string, unknown>;

export class FixtureGameRecordSource implements GameRecordSource {
  async characters(_credential: string, role: GameRole): Promise<GameCharacter[]> {
    const now = new Date().toISOString();
    return [
      this.character(role.uid, "10000089", "芙宁娜", "Water", 90, 5, 2, "静水流涌之辉", now),
      this.character(role.uid, "10000075", "流浪者", "Wind", 90, 5, 0, "图莱杜拉的回忆", now),
      this.character(role.uid, "10000084", "林尼", "Fire", 80, 5, 1, "最初的大魔术", now),
    ];
  }

  async characterDetail(credential: string, role: GameRole, avatarId: string): Promise<GameCharacter> {
    const value = (await this.characters(credential, role)).find((item) => item.avatar_id === avatarId)
      ?? this.character(role.uid, avatarId, "旅行者", "None", 90, 5, 0, "无锋剑", new Date().toISOString());
    return { ...value, payload: this.detail(value) };
  }

  private character(uid: string, avatarId: string, name: string, element: string, level: number, rarity: number, constellation: number, weapon: string, updatedAt: string): GameCharacter {
    return { uid, avatar_id: avatarId, name, element, level, rarity, constellation, fetter: 10, weapon_name: weapon, weapon_level: 90, icon_url: null, updated_at: updatedAt, payload: { avatar_id: avatarId } };
  }

  private detail(value: GameCharacter): JSONValue {
    return {
      base: { id: Number(value.avatar_id), name: value.name, icon: value.icon_url, level: value.level, rarity: value.rarity, element: value.element, fetter: value.fetter },
      weapon: { id: 11513, name: value.weapon_name, rarity: 5, level: value.weapon_level, affix_level: 1, main_property: { name: "基础攻击力", value: "542" }, sub_property: { name: "暴击率", value: "44.1%" } },
      selected_properties: [
        { name: "生命值上限", value: "39182", add_value: "12891" }, { name: "攻击力", value: "1421", add_value: "612" },
        { name: "防御力", value: "742", add_value: "226" }, { name: "元素精通", value: "84" },
      ],
      skills: [{ name: "普通攻击", level: 6 }, { name: "元素战技", level: 10 }, { name: "元素爆发", level: 10 }],
      constellations: Array.from({ length: 6 }, (_, index) => ({ name: `${index + 1} 命`, is_activated: index < value.constellation })),
      recommend_relic_property: { sand_properties: ["生命值%"], goblet_properties: ["水元素伤害"], circlet_properties: ["暴击率", "暴击伤害"], sub_properties: ["暴击率", "暴击伤害", "生命值%"] },
      relics: [1, 2, 3, 4, 5].map((pos) => ({ id: pos, name: `测试圣遗物 ${pos}`, set_name: "黄金剧团", rarity: 5, level: 20, pos, main_property: { name: pos === 3 ? "生命值%" : "攻击力", value: pos === 3 ? "46.6%" : "311" }, sub_properties: [{ name: "暴击率", value: "7.8%" }, { name: "暴击伤害", value: "14.0%" }] })),
    };
  }
}
