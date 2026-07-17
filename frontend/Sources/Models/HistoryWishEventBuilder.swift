import Foundation

extension HistoryWishEvent {
    static func make(events: [GachaEvent], records: [WishRecord]) -> [HistoryWishEvent] {
        let banners = bannerGroups(events: events)
        let samples = itemSamples(records)
        return eventGroups(events).compactMap { group in
            makeEvent(group: group, events: events, records: records, banners: banners, samples: samples)
        }
        .filter { $0.total > 0 }
        .sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt > $1.startedAt }
            return typeOrder($0.gachaType) < typeOrder($1.gachaType)
        }
    }

    private static func makeEvent(
        group: [GachaEvent],
        events: [GachaEvent],
        records: [WishRecord],
        banners: [HistoryWishPeriodKey: [HistoryWishBanner]],
        samples: [Int: [String: WishRecord]]
    ) -> HistoryWishEvent? {
        let sorted = group.sorted { typeOrder($0.gachaType) < typeOrder($1.gachaType) }
        guard let event = sorted.first,
              let startedAt = event.startedAt,
              let endedAt = event.endedAt else { return nil }
        let types = Set(sorted.map(\.gachaType))
        let matched = records.filter {
            types.contains($0.gachaType) && startedAt <= $0.time && $0.time <= endedAt
        }
        let key = HistoryWishPeriodKey(startedAt: startedAt, endedAt: endedAt)
        return HistoryWishEvent(
            id: event.id,
            version: event.version,
            name: unique(sorted.map(\.name)).joined(separator: " · "),
            gachaType: event.gachaType.normalizedGachaType,
            bannerUrl: event.bannerUrl,
            banners: banners[key] ?? [],
            phaseTitle: phaseTitle(event: event, events: events),
            startedAt: startedAt,
            endedAt: endedAt,
            total: matched.count,
            orangeUp: upItems(
                names: unique(sorted.flatMap(\.orangeUp)), rank: 5,
                eventRecords: matched, samples: samples
            ),
            purpleUp: upItems(
                names: unique(sorted.flatMap(\.purpleUp)), rank: 4,
                eventRecords: matched, samples: samples
            ),
            summary: aggregate(matched, rank: 5),
            purple: aggregate(matched, rank: 4),
            blue: aggregate(matched, rank: 3)
        )
    }

    private static func eventGroups(_ events: [GachaEvent]) -> [[GachaEvent]] {
        Dictionary(grouping: events.compactMap { event -> (HistoryWishGroupKey, GachaEvent)? in
            guard let startedAt = event.startedAt, let endedAt = event.endedAt else { return nil }
            return (
                HistoryWishGroupKey(
                    type: event.gachaType.normalizedGachaType,
                    startedAt: startedAt,
                    endedAt: endedAt
                ),
                event
            )
        }, by: \.0).values.map { $0.map(\.1) }
    }

    private static func phaseTitle(event: GachaEvent, events: [GachaEvent]) -> String {
        let periods = Set(events.filter {
            $0.version == event.version && $0.gachaType.normalizedGachaType == "301"
        }.compactMap(\.startedAt)).sorted()
        let index = event.startedAt.flatMap { periods.firstIndex(of: $0) } ?? 0
        return "\(event.version.nonempty ?? "未知")版本 \(index == 0 ? "上半" : "下半")"
    }

    private static func itemSamples(_ records: [WishRecord]) -> [Int: [String: WishRecord]] {
        records.reduce(into: [:]) { result, record in
            if result[record.rank]?[record.name] == nil {
                result[record.rank, default: [:]][record.name] = record
            }
        }
    }

    private static func upItems(
        names: [String], rank: Int, eventRecords: [WishRecord],
        samples: [Int: [String: WishRecord]]
    ) -> [HistoryWishItem] {
        let counts = Dictionary(grouping: eventRecords.filter { $0.rank == rank }, by: \.name)
        var indexed: [(Int, HistoryWishItem)] = []
        for (index, name) in names.enumerated() {
            let matches = counts[name] ?? []
            let sample = matches.first ?? samples[rank]?[name]
            let fallbackID = "up-" + String(rank) + "-" + name
            let id = sample?.itemId ?? fallbackID
            let item = HistoryWishItem(
                id: id, name: name,
                itemType: sample?.itemType ?? "", rank: rank,
                iconUrl: sample?.iconUrl, count: matches.count
            )
            indexed.append((index, item))
        }
        return indexed.sorted {
            $0.1.count != $1.1.count ? $0.1.count > $1.1.count : $0.0 < $1.0
        }
        .map(\.1)
    }

    private static func aggregate(_ records: [WishRecord], rank: Int) -> [HistoryWishItem] {
        Dictionary(grouping: records.filter { $0.rank == rank }) {
            $0.itemId.nonempty ?? $0.name
        }.values.compactMap { group in
            guard let first = group.first else { return nil }
            return HistoryWishItem(
                id: first.itemId.nonempty ?? first.name, name: first.name,
                itemType: first.itemType, rank: first.rank,
                iconUrl: first.iconUrl, count: group.count
            )
        }
        .sorted {
            $0.count != $1.count
                ? $0.count > $1.count
                : $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    private static func bannerGroups(
        events: [GachaEvent]
    ) -> [HistoryWishPeriodKey: [HistoryWishBanner]] {
        var groups: [HistoryWishPeriodKey: [HistoryWishBanner]] = [:]
        for event in events {
            guard let startedAt = event.startedAt, let endedAt = event.endedAt else { continue }
            let key = HistoryWishPeriodKey(startedAt: startedAt, endedAt: endedAt)
            groups[key, default: []].append(HistoryWishBanner(
                id: event.id, name: event.name,
                gachaType: event.gachaType, bannerUrl: event.bannerUrl
            ))
        }
        return groups.mapValues { values in
            values.sorted { typeOrder($0.gachaType) < typeOrder($1.gachaType) }
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func typeOrder(_ value: String) -> Int {
        ["301", "400", "302", "500"].firstIndex(of: value) ?? 9
    }
}

private struct HistoryWishGroupKey: Hashable {
    let type: String
    let startedAt: Date
    let endedAt: Date
}

private struct HistoryWishPeriodKey: Hashable {
    let startedAt: Date
    let endedAt: Date
}
