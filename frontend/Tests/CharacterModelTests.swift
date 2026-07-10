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
                "selected_properties": [{"name": "生命值上限", "value": "39182"}]
              },
              "updated_at": "2026-06-11T08:00:00Z"
            }
            """.utf8
        )
        let character = try JSONDecoder.api.decode(GameCharacter.self, from: data)
        #expect(character.elementTitle == "水")
        #expect(character.payload?.weapon?.name == "静水流涌之辉")
        #expect(character.payload?.selectedProperties?.first?.name == "生命值上限")
    }
}
