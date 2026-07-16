import Foundation

struct WishOverviewSummary: Equatable, Sendable {
    let total: Int
    let fiveStarCount: Int
    let fourStarCount: Int
    let oldestTime: Date?
    let newestTime: Date?

    init(records: [WishRecord]) {
        total = records.count
        fiveStarCount = records.count { $0.rank == 5 }
        fourStarCount = records.count { $0.rank == 4 }
        oldestTime = records.last?.time
        newestTime = records.first?.time
    }
}

struct WishPresentationCache: Sendable {
    let resultCatalog: WishResultCatalog
    let overviewSummary: WishOverviewSummary
    let pityEntries: [WishPityEntry]

    static func build(records: [WishRecord]) async -> WishPresentationCache {
        await Task.detached(priority: .userInitiated) {
            WishPresentationCache(
                resultCatalog: WishResultCatalog(records: records),
                overviewSummary: WishOverviewSummary(records: records),
                pityEntries: WishHistoryPresentation.entries(
                    records: records,
                    selectedGachaType: nil
                )
            )
        }.value
    }
}
