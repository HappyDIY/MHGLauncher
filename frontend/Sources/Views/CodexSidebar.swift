import AppKit
import SwiftUI

struct CodexSidebar: View {
    @Bindable var store: LauncherStore

    var body: some View {
        List {
            ForEach(CodexSidebarSection.allCases) { section in
                if let title = section.title {
                    Section(title) { rows(for: section) }
                } else {
                    Section { rows(for: section) }
                }
            }
        }
        .listStyle(.sidebar)
        .controlSize(.regular)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background {
            CodexSidebarBackground()
                .ignoresSafeArea()
        }
        .navigationTitle("MHGLauncher")
        .navigationSplitViewColumnWidth(
            min: CodexSidebarStyle.minimumWidth,
            ideal: CodexSidebarStyle.idealWidth,
            max: CodexSidebarStyle.maximumWidth
        )
    }

    @ViewBuilder
    private func rows(for section: CodexSidebarSection) -> some View {
        ForEach(section.destinations) { destination in
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
                    .font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, CodexSidebarStyle.rowHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: CodexSidebarStyle.rowHeight)
            .background(rowBackground, in: rowShape)
            .contentShape(rowShape)
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
        if isSelected { return Color.primary.opacity(CodexSidebarStyle.selectionOpacity) }
        return Color.primary.opacity(isHovering ? CodexSidebarStyle.hoverOpacity : 0)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CodexSidebarStyle.rowCornerRadius, style: .continuous)
    }
}

enum CodexSidebarSection: CaseIterable, Identifiable {
    case primary
    case gameData
    case services

    var id: Self { self }

    var title: String? {
        switch self {
        case .primary: nil
        case .gameData: "游戏资料"
        case .services: "服务"
        }
    }

    var destinations: [Destination] {
        switch self {
        case .primary: [.home, .game]
        case .gameData: [.wishes, .gachaHistory, .notes, .characters, .achievements]
        case .services: [.cloudSync, .notifications, .account]
        }
    }
}

struct CodexSidebarBackground: View {
    var body: some View {
        CodexSidebarVibrancy()
    }
}

struct CodexSidebarVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        Self.makeEffectView()
    }

    static func makeEffectView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum CodexSidebarStyle {
    static let minimumWidth: CGFloat = 180
    static let idealWidth: CGFloat = 200
    static let maximumWidth: CGFloat = 240
    static let rowHeight: CGFloat = 32
    static let rowCornerRadius: CGFloat = 7
    static let rowSpacing: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 2
    static let iconSize: CGFloat = 18
    static let selectionOpacity = 0.12
    static let hoverOpacity = 0.055
    static let rowInsets = EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0)
}
