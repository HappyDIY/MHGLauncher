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

    // 是否为具备 50/50 机制的限定卡池（角色活动/武器活动）。
    var isLimitedPool: Bool { gachaType == "301" || gachaType == "302" }

    // 每个限定五星所需的原石数量：依据平均 UP 出金抽数 × 单抽 160 原石推算。
    // 旧版后端未提供平均 UP 出金时返回 0。
    var primogemsPerLimitedFiveStar: Int {
        averageUpPity.map { Int(($0 * 160).rounded()) } ?? 0
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

    var poolLabel: String {
        switch gachaType {
        case "301", "400": "限定角色"
        case "302": "限定武器"
        case "200": "常驻角色"
        default: poolName
        }
    }

    var poolGradient: LinearGradient {
        switch gachaType {
        case "301", "400":
            LinearGradient(
                colors: [Color(red: 0.85, green: 0.35, blue: 0.72), .purple, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "302":
            LinearGradient(
                colors: [Color(red: 0.96, green: 0.55, blue: 0.18), .red],
                startPoint: .top,
                endPoint: .bottom
            )
        case "200":
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.55, blue: 0.9), .indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            LinearGradient(
                colors: [.blue, .teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
