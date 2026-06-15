import SwiftUI

extension WishRecord {
    var normalizedGachaType: String {
        gachaType == "400" ? "301" : gachaType
    }
}

enum WishResultMode: String, CaseIterable, Identifiable {
    case character
    case weapon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .character: "角色"
        case .weapon: "武器"
        }
    }

    var itemType: String { title }
}

struct WishResultItem: Identifiable, Equatable {
    let id: String
    let name: String
    let rank: Int
    let iconUrl: URL?
    let count: Int

    var constellation: Int {
        max(count - 1, 0)
    }
}

extension Array where Element == WishRecord {
    func resultItems(for mode: WishResultMode) -> [WishResultItem] {
        let groups = Dictionary(grouping: filter {
            $0.itemType == mode.itemType && $0.rank >= 4
        }, by: \.itemId)

        return groups.values.compactMap { records in
            guard let record = records.first else { return nil }
            return WishResultItem(
                id: record.itemId,
                name: record.name,
                rank: record.rank,
                iconUrl: records.compactMap(\.iconUrl).first,
                count: records.count
            )
        }
        .sorted {
            if $0.rank != $1.rank {
                return $0.rank > $1.rank
            }
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }
}

extension WishBannerDetail {
    var poolName: String {
        switch gachaType {
        case "100": "新手祈愿"
        case "200": "常驻祈愿"
        case "301": "角色活动祈愿"
        case "302": "武器活动祈愿"
        default: "卡池 \(gachaType)"
        }
    }

    var poolIcon: String {
        switch gachaType {
        case "301": "person.2.fill"
        case "302": "shield.lefthalf.filled"
        case "200": "star.circle.fill"
        default: "sparkles"
        }
    }

    var poolAccent: Color {
        switch gachaType {
        case "301": .cyan
        case "302": .orange
        case "200": .purple
        default: .blue
        }
    }
}
