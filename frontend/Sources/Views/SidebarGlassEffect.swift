import AppKit
import SwiftUI

struct SidebarGlassEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarGlassStyleView {
        SidebarGlassStyleView()
    }

    func updateNSView(_ nsView: SidebarGlassStyleView, context: Context) {
        nsView.applyStyle()
    }
}

final class SidebarGlassStyleView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()
    }

    override func layout() {
        super.layout()
        applyStyle()
    }

    func applyStyle() {
        var ancestor = superview
        while let view = ancestor {
            if let glassView = view as? NSGlassEffectView {
                glassView.style = .clear
                let interactiveSelector = NSSelectorFromString("setEffectIsInteractive:")
                if glassView.responds(to: interactiveSelector) {
                    glassView.setValue(true, forKey: "effectIsInteractive")
                }
                return
            }
            ancestor = view.superview
        }
    }
}
