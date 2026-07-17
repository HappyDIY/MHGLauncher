import Foundation

enum HistoryWishCategory: String, CaseIterable, Identifiable, Sendable {
    case character = "角色"
    case weapon = "武器"

    var id: Self { self }

    var icon: String {
        switch self {
        case .character: "person.2.fill"
        case .weapon: "shield.lefthalf.filled"
        }
    }

    func includes(gachaType: String) -> Bool {
        switch self {
        case .character: gachaType.normalizedGachaType == "301"
        case .weapon: gachaType == "302"
        }
    }

    func wishes(in values: [HistoryWishEvent]) -> [HistoryWishEvent] {
        values.filter { includes(gachaType: $0.gachaType) }
    }

    func banners(in values: [HistoryWishBanner]) -> [HistoryWishBanner] {
        values.filter { includes(gachaType: $0.gachaType) }
    }
}
