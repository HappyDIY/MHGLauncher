import AppKit
import SwiftUI

struct CodexSidebar: View {
    @Bindable var store: LauncherStore

    var body: some View {
        List(Destination.allCases) { destination in
            CodexSidebarRow(
                destination: destination,
                isSelected: store.selectedDestination == destination
            ) {
                store.selectedDestination = destination
            }
            .listRowInsets(CodexSidebarStyle.rowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background {
            CodexSidebarBackground()
                .ignoresSafeArea()
        }
        .navigationTitle("MHGLauncher")
        .navigationSplitViewColumnWidth(
            min: CodexSidebarStyle.minimumWidth,
            ideal: CodexSidebarStyle.idealWidth
        )
    }
}

private struct CodexSidebarRow: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    let destination: Destination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CodexSidebarStyle.rowSpacing) {
                Image(systemName: destination.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: CodexSidebarStyle.iconSize)
                    .motionSymbolBounce(value: isSelected)
                Text(destination.rawValue)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, CodexSidebarStyle.rowHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: CodexSidebarStyle.rowHeight)
            .background(rowBackground, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .motionAnimation(.micro, value: isHovering)
        .onHover { isHovering = $0 && isEnabled }
        .onChange(of: isEnabled) {
            if !isEnabled { isHovering = false }
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        return Color.primary.opacity(isHovering ? 0.055 : 0)
    }
}

struct CodexSidebarBackground: View {
    var body: some View {
        ZStack {
            CodexSidebarVibrancy()
            Color(nsColor: .windowBackgroundColor)
                .opacity(CodexSidebarStyle.surfaceOpacity)
        }
        .overlay(alignment: .trailing) {
            Color.primary.opacity(0.06)
                .frame(width: 0.5)
        }
        .shadow(color: .black.opacity(0.07), radius: 8, x: 3)
    }
}

struct CodexSidebarVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        Self.makeEffectView()
    }

    static func makeEffectView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum CodexSidebarStyle {
    static let surfaceOpacity = 0.70
    static let minimumWidth: CGFloat = 220
    static let idealWidth: CGFloat = 260
    static let rowHeight: CGFloat = 32
    static let rowSpacing: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 10
    static let iconSize: CGFloat = 18
    static let rowInsets = EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12)
}
