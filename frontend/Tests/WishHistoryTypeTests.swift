import Foundation
import Testing
@testable import MHGLauncher

@Suite("历史祈愿卡池类型")
struct WishHistoryTypeTests {
    @Test("双角色卡池按原始类型独立匹配")
    func separatesConcurrentCharacterBanners() {
        let events = [
            event(id: "first", type: "301", name: "角色池一"),
            event(id: "second", type: "400", name: "角色池二")
        ]
        let records = [
            record(id: "1", name: "角色一", type: "301"),
            record(id: "2", name: "角色二", type: "400")
        ]

        let history = HistoryWishEvent.make(events: events, records: records)

        #expect(history.count == 2)
        #expect(history.first { $0.id == "first" }?.summary.map(\.name) == ["角色一"])
        #expect(history.first { $0.id == "second" }?.summary.map(\.name) == ["角色二"])
    }

    private func event(id: String, type: String, name: String) -> GachaEvent {
        GachaEvent(
            id: id, version: "6.7", gachaType: type, name: name,
            startedAt: date("2026-06-18T00:00:00Z"),
            endedAt: date("2026-07-08T00:00:00Z"),
            orangeUp: [], purpleUp: [], bannerUrl: nil,
            updatedAt: date("2026-06-18T00:00:00Z")
        )
    }

    private func record(id: String, name: String, type: String) -> WishRecord {
        WishRecord(
            id: id, uid: "100000001", gachaType: type,
            itemId: id, name: name, itemType: "角色", rank: 5,
            time: date("2026-06-20T12:00:00Z"), iconUrl: nil
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
    }
}
