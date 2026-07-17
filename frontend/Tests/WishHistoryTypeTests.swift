import Foundation
import Testing
@testable import MHGLauncher

@Suite("历史祈愿卡池类型")
struct WishHistoryTypeTests {
    @Test("分类筛选同时区分列表与同期横幅")
    func filtersCategories() {
        #expect(HistoryWishCategory.character.includes(gachaType: "301"))
        #expect(HistoryWishCategory.character.includes(gachaType: "400"))
        #expect(!HistoryWishCategory.character.includes(gachaType: "302"))
        #expect(HistoryWishCategory.weapon.includes(gachaType: "302"))
        #expect(!HistoryWishCategory.weapon.includes(gachaType: "301"))

        let banners = [
            HistoryWishBanner(id: "role-1", name: "角色一", gachaType: "301", bannerUrl: nil),
            HistoryWishBanner(id: "role-2", name: "角色二", gachaType: "400", bannerUrl: nil),
            HistoryWishBanner(id: "weapon", name: "武器", gachaType: "302", bannerUrl: nil)
        ]
        #expect(HistoryWishCategory.character.banners(in: banners).map(\.id) == ["role-1", "role-2"])
        #expect(HistoryWishCategory.weapon.banners(in: banners).map(\.id) == ["weapon"])
    }

    @Test("双角色卡池合并为同一祈愿时段")
    func mergesConcurrentCharacterBanners() {
        let events = [
            event(id: "first", type: "301", name: "角色池一"),
            event(id: "second", type: "400", name: "角色池二")
        ]
        let records = [
            record(id: "1", name: "角色一", type: "301"),
            record(id: "2", name: "角色二", type: "400")
        ]

        let history = HistoryWishEvent.make(events: events, records: records)

        #expect(history.count == 1)
        #expect(history.first?.total == 2)
        #expect(Set(history.first?.summary.map(\.name) ?? []) == ["角色一", "角色二"])
        #expect(history.first?.banners.map(\.name) == ["角色池一", "角色池二"])
        #expect(history.first?.phaseTitle == "6.7版本 上半")
    }

    @Test("同版本祈愿时段区分上下半")
    func labelsVersionPhases() {
        let events = [
            event(id: "upper", type: "301", name: "上半卡池"),
            event(
                id: "lower", type: "301", name: "下半卡池",
                start: "2026-07-09T00:00:00Z", end: "2026-07-29T00:00:00Z"
            )
        ]
        let records = [
            record(id: "1", name: "角色一", type: "301"),
            record(
                id: "2", name: "角色二", type: "301",
                time: "2026-07-20T12:00:00Z"
            )
        ]

        let history = HistoryWishEvent.make(events: events, records: records)

        #expect(Set(history.map(\.phaseTitle)) == ["6.7版本 上半", "6.7版本 下半"])
    }

    private func event(
        id: String,
        type: String,
        name: String,
        start: String = "2026-06-18T00:00:00Z",
        end: String = "2026-07-08T00:00:00Z"
    ) -> GachaEvent {
        GachaEvent(
            id: id, version: "6.7", gachaType: type, name: name,
            startedAt: date(start), endedAt: date(end),
            orangeUp: [], purpleUp: [], bannerUrl: nil,
            updatedAt: date("2026-06-18T00:00:00Z")
        )
    }

    private func record(
        id: String,
        name: String,
        type: String,
        time: String = "2026-06-20T12:00:00Z"
    ) -> WishRecord {
        WishRecord(
            id: id, uid: "100000001", gachaType: type,
            itemId: id, name: name, itemType: "角色", rank: 5,
            time: date(time), iconUrl: nil
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
    }
}
