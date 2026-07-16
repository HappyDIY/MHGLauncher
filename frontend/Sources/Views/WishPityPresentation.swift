import Foundation

// 保底计数必须在显示筛选之前按卡池计算。

struct WishPityEntry: Identifiable {
    var id: String { record.id }
    let record: WishRecord
    let pity: Int
}

enum WishHistoryPresentation {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func entries(
        records: [WishRecord],
        selectedGachaType: String?
    ) -> [WishPityEntry] {
        let scoped = records.filter {
            selectedGachaType == nil || $0.normalizedGachaType == selectedGachaType
        }
        var counters: [String: Int] = [:]
        var pityByID: [String: Int] = [:]
        for record in scoped.reversed() {
            let pool = record.normalizedGachaType
            let pity = (counters[pool] ?? 0) + 1
            counters[pool] = record.rank == 5 ? 0 : pity
            pityByID[record.id] = pity
        }
        return scoped.map { WishPityEntry(record: $0, pity: pityByID[$0.id] ?? 1) }
    }

    static func dateTime(_ date: Date) -> String {
        return formatter.string(from: date)
    }
}
