import AppKit
import Testing
@testable import MHGLauncher

@Suite("Codex 侧边栏样式")
struct CodexSidebarTests {
    @Test("使用菜单振动材质而非液态玻璃")
    @MainActor
    func usesMenuVibrancy() {
        let effectView = CodexSidebarVibrancy.makeEffectView()

        #expect(effectView.material == .menu)
        #expect(effectView.blendingMode == .behindWindow)
        #expect(effectView.state == .active)
    }

    @Test("采用 Codex 的七成侧栏表面")
    func usesCodexSurfaceMetrics() {
        #expect(CodexSidebarStyle.surfaceOpacity == 0.70)
        #expect(CodexSidebarStyle.idealWidth == 260)
        #expect(CodexSidebarStyle.rowHeight == 32)
    }
}
