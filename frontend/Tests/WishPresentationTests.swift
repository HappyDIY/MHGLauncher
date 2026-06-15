import Foundation
import Testing
@testable import MHGLauncher

@Suite("祈愿展示数据")
struct WishPresentationTests {
    @Test("五星条目同时解码累计位置与单次保底")
    func decodesBannerItemPity() throws {
        let data = Data(
            """
            {
              "name": "芙宁娜",
              "item_id": "10000089",
              "item_type": "角色",
              "rank": 5,
              "icon_url": null,
              "pull_number": 2155,
              "pity": 27,
              "time": "2026-06-14T21:05:00"
            }
            """.utf8
        )

        let item = try JSONDecoder.api.decode(WishBannerItem.self, from: data)

        #expect(item.pullNumber == 2_155)
        #expect(item.pity == 27)
    }

    @Test("角色成果按物品聚合并计算命座")
    func aggregatesCharacterResults() throws {
        let records = [
            record(id: "1", itemId: "1001", name: "测试角色", type: "角色", rank: 5),
            record(id: "2", itemId: "1001", name: "测试角色", type: "角色", rank: 5),
            record(id: "3", itemId: "2001", name: "测试武器", type: "武器", rank: 5),
            record(id: "4", itemId: "1002", name: "三星角色", type: "角色", rank: 3)
        ]

        let result = try #require(records.resultItems(for: .character).first)

        #expect(records.resultItems(for: .character).count == 1)
        #expect(result.count == 2)
        #expect(result.constellation == 1)
    }

    @Test("武器成果显示持有数量并按星级排序")
    func aggregatesWeaponResults() {
        let records = [
            record(id: "1", itemId: "2001", name: "四星武器", type: "武器", rank: 4),
            record(id: "2", itemId: "2002", name: "五星武器", type: "武器", rank: 5),
            record(id: "3", itemId: "2001", name: "四星武器", type: "武器", rank: 4)
        ]

        let results = records.resultItems(for: .weapon)

        #expect(results.map(\.name) == ["五星武器", "四星武器"])
        #expect(results[1].count == 2)
    }

    private func record(
        id: String,
        itemId: String,
        name: String,
        type: String,
        rank: Int
    ) -> WishRecord {
        WishRecord(
            id: id,
            uid: "100000001",
            gachaType: "301",
            itemId: itemId,
            name: name,
            itemType: type,
            rank: rank,
            time: .now,
            iconUrl: nil
        )
    }
}
