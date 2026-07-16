import Foundation

struct HistoryWishItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let itemType: String
    let rank: Int
    let iconUrl: URL?
    let count: Int
}

struct HistoryWishEvent: Identifiable, Equatable, Sendable {
    let id: String
    let version: String
    let name: String
    let gachaType: String
    let bannerUrl: URL?
    let startedAt: Date
    let endedAt: Date
    let total: Int
    let orangeUp: [HistoryWishItem]
    let purpleUp: [HistoryWishItem]
    let summary: [HistoryWishItem]
    let purple: [HistoryWishItem]
    let blue: [HistoryWishItem]

    var timeSpan: String {
        "\(Self.dayString(startedAt)) - \(Self.dayString(endedAt))"
    }

    var totalText: String { "总计 \(total) 抽" }

    static func make(events: [GachaEvent], records: [WishRecord]) -> [HistoryWishEvent] {
        let recordsByType = Dictionary(grouping: records, by: \.normalizedGachaType)
        let samples = records.reduce(into: [Int: [String: WishRecord]]()) { result, record in
            if result[record.rank]?[record.name] == nil {
                result[record.rank, default: [:]][record.name] = record
            }
        }
        return events.compactMap { event -> HistoryWishEvent? in
            guard let startedAt = event.startedAt, let endedAt = event.endedAt else { return nil }
            let eventRecords = (recordsByType[event.gachaType.normalizedGachaType] ?? [])
                .filter { startedAt <= $0.time && $0.time <= endedAt }
            return HistoryWishEvent(
                id: event.id,
                version: event.version,
                name: event.name,
                gachaType: event.gachaType,
                bannerUrl: event.bannerUrl,
                startedAt: startedAt,
                endedAt: endedAt,
                total: eventRecords.count,
                orangeUp: upItems(names: event.orangeUp, rank: 5, eventRecords: eventRecords, samples: samples),
                purpleUp: upItems(names: event.purpleUp, rank: 4, eventRecords: eventRecords, samples: samples),
                summary: aggregate(eventRecords, rank: 5),
                purple: aggregate(eventRecords, rank: 4),
                blue: aggregate(eventRecords, rank: 3)
            )
        }
        .filter { $0.total > 0 }
        .sorted { left, right in
            if left.startedAt != right.startedAt { return left.startedAt > right.startedAt }
            return typeOrder(left.gachaType) < typeOrder(right.gachaType)
        }
    }

    private static func upItems(
        names: [String],
        rank: Int,
        eventRecords: [WishRecord],
        samples: [Int: [String: WishRecord]]
    ) -> [HistoryWishItem] {
        let counts = Dictionary(grouping: eventRecords.filter { $0.rank == rank }, by: \.name)
        return names.enumerated().map { index, name in
            let matches = counts[name] ?? []
            let sample = matches.first ?? samples[rank]?[name]
            return (
                index,
                HistoryWishItem(
                    id: sample?.itemId ?? "up-\(rank)-\(name)",
                    name: name,
                    itemType: sample?.itemType ?? "",
                    rank: rank,
                    iconUrl: sample?.iconUrl,
                    count: matches.count
                )
            )
        }
        .sorted {
            if $0.1.count != $1.1.count { return $0.1.count > $1.1.count }
            return $0.0 < $1.0
        }
        .map(\.1)
    }

    private static func aggregate(_ records: [WishRecord], rank: Int) -> [HistoryWishItem] {
        Dictionary(grouping: records.filter { $0.rank == rank }) {
            $0.itemId.nonempty ?? $0.name
        }
        .values
        .compactMap { group in
            guard let first = group.first else { return nil }
            return HistoryWishItem(
                id: first.itemId.nonempty ?? first.name,
                name: first.name,
                itemType: first.itemType,
                rank: first.rank,
                iconUrl: first.iconUrl,
                count: group.count
            )
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    private static func typeOrder(_ value: String) -> Int {
        switch value.normalizedGachaType {
        case "301": 0
        case "302": 1
        case "500": 2
        default: 9
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    private static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

extension String {
    var normalizedGachaType: String { self == "400" ? "301" : self }
}
