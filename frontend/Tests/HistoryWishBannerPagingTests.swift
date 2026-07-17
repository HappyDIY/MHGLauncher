import Testing
@testable import MHGLauncher

@Suite("同期祈愿横幅分页")
struct HistoryWishBannerPagingTests {
    @Test("横幅分页支持首尾禁用与相邻切换")
    func movesBetweenAdjacentBanners() {
        let first = HistoryWishBannerPaging(ids: ["a", "b", "c"], selectedID: "a")
        #expect(first.page == 1)
        #expect(!first.canGoPrevious)
        #expect(first.canGoNext)
        #expect(first.adjacentID(offset: 1) == "b")

        let middle = HistoryWishBannerPaging(ids: ["a", "b", "c"], selectedID: "b")
        #expect(middle.page == 2)
        #expect(middle.currentID == "b")
        #expect(middle.adjacentID(offset: -1) == "a")
        #expect(middle.adjacentID(offset: 1) == "c")

        let last = HistoryWishBannerPaging(ids: ["a", "b", "c"], selectedID: "c")
        #expect(last.canGoPrevious)
        #expect(!last.canGoNext)
        #expect(last.adjacentID(offset: 1) == nil)
    }
}
