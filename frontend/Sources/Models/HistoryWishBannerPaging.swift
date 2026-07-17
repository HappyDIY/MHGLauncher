import Foundation

struct HistoryWishBannerPaging: Equatable, Sendable {
    let ids: [String]
    let selectedID: String?

    var index: Int? {
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            return index
        }
        return ids.isEmpty ? nil : 0
    }

    var page: Int { index.map { $0 + 1 } ?? 0 }
    var count: Int { ids.count }
    var currentID: String? { index.map { ids[$0] } }
    var canGoPrevious: Bool { index.map { $0 > 0 } ?? false }
    var canGoNext: Bool { index.map { $0 + 1 < ids.count } ?? false }

    func adjacentID(offset: Int) -> String? {
        guard let index else { return nil }
        let target = index + offset
        guard ids.indices.contains(target) else { return nil }
        return ids[target]
    }
}
