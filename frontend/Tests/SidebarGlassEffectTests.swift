import AppKit
import Testing
@testable import MHGLauncher

@Suite("侧边栏玻璃材质")
struct SidebarGlassEffectTests {
    @Test("复用导航栏已有玻璃图层并切换为透明样式")
    @MainActor
    func configuresAncestorGlassView() {
        let glassView = NSGlassEffectView()
        glassView.style = .regular
        let contentView = NSView()
        let styleView = SidebarGlassStyleView()

        glassView.contentView = contentView
        contentView.addSubview(styleView)
        styleView.applyStyle()

        #expect(glassView.style == .clear)
    }
}
