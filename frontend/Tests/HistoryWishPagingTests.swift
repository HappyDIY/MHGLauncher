import Testing
@testable import MHGLauncher

@Suite("历史卡池分页")
struct HistoryWishPagingTests {
    @Test("分页支持首尾禁用与相邻切换")
    func movesBetweenAdjacentEvents() {
        let first = HistoryWishPaging(ids: ["a", "b", "c"], selectedID: nil)
        #expect(first.page == 1)
        #expect(!first.canGoPrevious)
        #expect(first.canGoNext)
        #expect(first.adjacentID(offset: 1) == "b")

        let middle = HistoryWishPaging(ids: ["a", "b", "c"], selectedID: "b")
        #expect(middle.page == 2)
        #expect(middle.adjacentID(offset: -1) == "a")
        #expect(middle.adjacentID(offset: 1) == "c")

        let last = HistoryWishPaging(ids: ["a", "b", "c"], selectedID: "c")
        #expect(last.page == 3)
        #expect(last.canGoPrevious)
        #expect(!last.canGoNext)
        #expect(last.adjacentID(offset: 1) == nil)
    }
}
