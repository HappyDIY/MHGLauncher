import AppKit
import Foundation
import SwiftUI
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
                "skills": [{"skill_type":1,"name":"普通攻击","level":10}],
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
        #expect(character.payload?.skills?.first?.isCombatTalent == true)
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

        #expect(property.formattedAddValue == "+74.4%")
    }

    @Test("加载七元素图标资源")
    func loadElementIcons() {
        let names = [
            "ElementFire", "ElementWater", "ElementWind", "ElementElectric",
            "ElementGrass", "ElementIce", "ElementRock",
        ]
        for name in names {
            #expect(CharacterResources.image(named: name) != nil)
        }
    }

    @MainActor
    @Test("元素图标视图包含可见像素")
    func renderElementIcon() throws {
        let character = GameCharacter(
            uid: "100000001", avatarId: "10000095", name: "伊涅芙",
            element: "Electric", level: 90, rarity: 5, constellation: 0,
            fetter: 10, weaponName: "", weaponLevel: 1, iconUrl: nil,
            payload: nil, updatedAt: Date(timeIntervalSince1970: 0)
        )
        let renderer = ImageRenderer(content: CharacterElementIcon(character: character, size: 32))
        renderer.scale = 2
        let data = try #require(renderer.nsImage?.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let hasVisiblePixel = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1
            }
        }
        #expect(hasVisiblePixel)
    }
}
