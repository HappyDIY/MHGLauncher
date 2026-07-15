import Foundation
import Testing
@testable import MHGLauncher

@Suite("角色模型")
struct CharacterModelTests {
    @Test("解码角色详情负载")
    func decodeCharacterPayload() throws {
        let data = Data(
            """
            {
              "uid": "100000001",
              "avatar_id": "10000089",
              "name": "芙宁娜",
              "element": "Water",
              "level": 90,
              "rarity": 5,
              "constellation": 2,
              "fetter": 10,
              "weapon_name": "静水流涌之辉",
              "weapon_level": 90,
              "icon_url": null,
              "payload": {
                "weapon": {"name": "静水流涌之辉", "level": 90},
                "selected_properties": [{"name": "生命值上限", "value": "39182"}],
                "skills": [],
                "constellations": []
              },
              "updated_at": "2026-06-11T08:00:00Z"
            }
            """.utf8
        )
        let character = try JSONDecoder.api.decode(GameCharacter.self, from: data)
        #expect(character.elementTitle == "水")
        #expect(character.payload?.weapon?.name == "静水流涌之辉")
        #expect(character.payload?.selectedProperties?.first?.name == "生命值上限")
        #expect(character.detailReady)
    }

    @Test("武器摘要不能冒充完整角色详情")
    func rejectSummaryAsDetail() throws {
        let data = Data(
            """
            {
              "uid": "100000001", "avatar_id": "10000089", "name": "芙宁娜",
              "element": "Water", "level": 90, "rarity": 5, "constellation": 2,
              "fetter": 10, "weapon_name": "静水流涌之辉", "weapon_level": 90,
              "icon_url": null, "payload": {"weapon": {"name": "静水流涌之辉"}},
              "updated_at": "2026-06-11T08:00:00Z"
            }
            """.utf8
        )
        let character = try JSONDecoder.api.decode(GameCharacter.self, from: data)
        #expect(!character.detailReady)
    }

    @Test("兼容米游社原始详情字段")
    func decodeRawDetailFields() throws {
        let property = try JSONDecoder.api.decode(
            CharacterProperty.self,
            from: Data(#"{"property_type":20,"base":"5%","add":"74.4%","final":"79.4%"}"#.utf8)
        )
        #expect(property.name == "暴击率")
        #expect(property.value == "79.4%")
        #expect(property.addValue == "74.4%")

        let relic = try JSONDecoder.api.decode(
            CharacterReliquary.self,
            from: Data(
                #"{"name":"金杯","set":{"name":"黄金剧团"},"pos":3,"sub_property_list":[{"property_type":22,"final":"14.0%"}]}"#.utf8
            )
        )
        #expect(relic.setName == "黄金剧团")
        #expect(relic.subProperties?.first?.name == "暴击伤害")

        let recommendation = try JSONDecoder.api.decode(
            CharacterRecommendation.self,
            from: Data(
                #"{"recommend_properties":{"sand_main_property_list":[6],"goblet_main_property_list":[6],"circlet_main_property_list":[22],"sub_property_list":[20,22]}}"#.utf8
            )
        )
        #expect(recommendation.sandProperties == ["攻击力百分比"])
        #expect(recommendation.circletProperties == ["暴击伤害"])
        #expect(recommendation.subProperties == ["暴击率", "暴击伤害"])
    }
}
