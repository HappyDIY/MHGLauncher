import AppKit
import Testing
@testable import MHGLauncher

@Suite("Finder 侧边栏样式")
struct CodexSidebarTests {
    @Test("使用系统侧边栏振动材质")
    @MainActor
    func usesSidebarVibrancy() {
        let effectView = CodexSidebarVibrancy.makeEffectView()

        #expect(effectView.material == .sidebar)
        #expect(effectView.blendingMode == .behindWindow)
        #expect(effectView.state == .active)
    }

    @Test("采用 Finder 风格宽度和分组")
    func usesFinderMetricsAndSections() {
        #expect(CodexSidebarStyle.minimumWidth == 180)
        #expect(CodexSidebarStyle.idealWidth == 200)
        #expect(CodexSidebarStyle.maximumWidth == 240)
        #expect(CodexSidebarStyle.rowHeight == 32)
        #expect(CodexSidebarStyle.rowCornerRadius == 7)
        #expect(CodexSidebarStyle.contentHorizontalPadding == 10)
        #expect(CodexSidebarStyle.rowHorizontalPadding == 10)
        #expect(CodexSidebarStyle.selectionOpacity == 0.12)
        let destinations = CodexSidebarSection.allCases.flatMap(\.destinations)
        #expect(destinations.count == Destination.allCases.count)
        #expect(Set(destinations) == Set(Destination.allCases))
        #expect(CodexSidebarSection.allCases.map(\.title) == [nil, "游戏资料", "服务"])
    }
}
