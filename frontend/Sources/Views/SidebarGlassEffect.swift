import AppKit
import SwiftUI

struct SidebarGlassEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .clear
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.style = .clear
    }
}
