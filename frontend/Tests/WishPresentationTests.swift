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

    @Test("角色重复数量不显示不存在的命座")
    func clampsConstellationAndReportsOverflow() {
        let item = WishResultItem(
            id: "1", name: "测试角色", rank: 5, iconUrl: nil, count: 9
        )
        #expect(item.constellation == 6)
        #expect(item.extraCopies == 2)
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

    @Test("五星筛选保留完整卡池保底计数")
    func pityIsCalculatedBeforeRankFiltering() throws {
        let records = [
            record(id: "3", itemId: "1003", name: "五星", type: "角色", rank: 5),
            record(id: "2", itemId: "1002", name: "三星", type: "武器", rank: 3),
            record(id: "1", itemId: "1001", name: "四星", type: "角色", rank: 4)
        ]
        let fiveStar = try #require(WishHistoryPresentation.entries(
            records: records, selectedGachaType: "301"
        ).first { $0.record.rank == 5 })
        #expect(fiveStar.pity == 3)
    }

    @Test("卡池统计兼容缺失限定指标的旧版后端")
    func decodeBannerDetailWithoutLimitedMetrics() throws {
        // 旧版后端未返回 average_up_pity / small_guarantee_win_rate 字段。
        // 前端须向后兼容，解码成功且限定指标为 nil，避免页面卡在「正在载入」。
        let data = Data(
            """
            {
              "uid": "230289829", "gacha_type": "301", "total": 10,
              "time_from": null, "time_to": null,
              "five_star_count": 1, "four_star_count": 1, "three_star_count": 8,
              "five_star_percent": 0.1, "four_star_percent": 0.1, "three_star_percent": 0.8,
              "max_pity": 10, "min_pity": 10, "average_pity": 10,
              "last_pity": 0, "last_purple_pity": 0, "guarantee_threshold": 90,
              "five_star_items": [], "four_star_items": []
            }
            """.utf8
        )
        let detail = try JSONDecoder.api.decode(WishBannerDetail.self, from: data)
        #expect(detail.averageUpPity == nil)
        #expect(detail.smallGuaranteeWinRate == nil)
        #expect(detail.primogemsPerLimitedFiveStar == 0)
    }

    @Test("历史祈愿按卡池时间聚合并保留未抽到 UP")
    func buildsHistoryWishEvents() throws {
        let event = GachaEvent(
            id: "e1",
            version: "5.7",
            gachaType: "301",
            name: "角色活动祈愿",
            startedAt: date("2026-06-18T10:00:00Z"),
            endedAt: date("2026-07-08T10:00:00Z"),
            orangeUp: ["丝柯克", "玛薇卡"],
            purpleUp: ["班尼特"],
            bannerUrl: nil,
            updatedAt: date("2026-06-18T10:00:00Z")
        )
        let records = [
            record(id: "1", itemId: "1001", name: "丝柯克", type: "角色", rank: 5),
            record(id: "2", itemId: "1002", name: "班尼特", type: "角色", rank: 4),
            record(id: "3", itemId: "11301", name: "冷刃", type: "武器", rank: 3)
        ]

        let history = HistoryWishEvent.make(events: [event], records: records)
        let item = try #require(history.first)

        #expect(item.total == 3)
        #expect(item.orangeUp.map(\.count) == [1, 0])
        #expect(item.summary.map(\.name) == ["丝柯克"])
        #expect(item.purple.map(\.name) == ["班尼特"])
        #expect(item.blue.map(\.name) == ["冷刃"])
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
            time: date("2026-06-20T12:00:00Z"),
            iconUrl: nil
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
    }
}
