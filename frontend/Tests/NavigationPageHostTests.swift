import SwiftUI
import Testing
@testable import MHGLauncher

@Suite("导航页面布局")
struct NavigationPageHostTests {
    @Test("完整提案尺寸不读取页面固有尺寸")
    func proposedSizeWins() {
        let size = StableNavigationLayout.resolvedSize(
            proposal: ProposedViewSize(width: 900, height: 700),
            fallback: CGSize(width: 320, height: 240)
        )

        #expect(size == CGSize(width: 900, height: 700))
    }

    @Test("缺失的提案维度才使用页面固有尺寸")
    func fallbackOnlyFillsMissingDimension() {
        let size = StableNavigationLayout.resolvedSize(
            proposal: ProposedViewSize(width: 900, height: nil),
            fallback: CGSize(width: 320, height: 240)
        )

        #expect(size == CGSize(width: 900, height: 240))
    }
}
