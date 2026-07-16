import Foundation

extension LauncherStore {
    @discardableResult
    func installWishRecords(_ records: [WishRecord]) async -> Bool {
        wishPresentationIntent &+= 1
        let intent = wishPresentationIntent
        let presentation = await WishPresentationCache.build(records: records)
        guard wishPresentationIntent == intent else { return false }

        // 先更新派生数据，最后发布原始记录，避免视图观察到不完整的一帧。
        wishResultCatalog = presentation.resultCatalog
        wishOverviewSummary = presentation.overviewSummary
        wishPityEntries = presentation.pityEntries
        wishes = records
        await refreshGachaHistoryPresentation()
        return wishPresentationIntent == intent
    }

    func clearWishPresentation() {
        wishPresentationIntent &+= 1
        gachaHistoryPresentationIntent &+= 1
        wishes = []
        wishResultCatalog = WishResultCatalog(records: [])
        wishOverviewSummary = WishOverviewSummary(records: [])
        wishPityEntries = []
        gachaHistory = []
    }

    func refreshGachaHistoryPresentation() async {
        gachaHistoryPresentationIntent &+= 1
        let intent = gachaHistoryPresentationIntent
        let events = value.gachaEvents
        let records = wishes
        let history = await Task.detached(priority: .userInitiated) {
            HistoryWishEvent.make(events: events, records: records)
        }.value
        guard gachaHistoryPresentationIntent == intent else { return }
        gachaHistory = history
    }

    func applyCompanionSnapshot(
        _ snapshot: CompanionSnapshot,
        uid: String,
        generation: Int
    ) async {
        guard isCurrentCompanionData(uid: uid, generation: generation),
              await installWishRecords(snapshot.wishes),
              isCurrentCompanionData(uid: uid, generation: generation) else {
            return
        }
        wishStatistics = snapshot.statistics
        bannerDetails = snapshot.bannerStatistics
        dailyNote = snapshot.note
        companionLoaded = true
    }
}
