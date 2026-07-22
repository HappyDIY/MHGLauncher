import AppKit
import SwiftUI

struct CodexSidebar: View {
    @Bindable var store: LauncherStore

    var body: some View {
        List(selection: $store.selectedDestination) {
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
            )
            .tag(destination)
        }
    }
}

private struct CodexSidebarRow: View {
    let destination: Destination
    let isSelected: Bool

    var body: some View {
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
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    static let idealWidth: CGFloat = 220
    static let maximumWidth: CGFloat = 320
    static let rowSpacing: CGFloat = 8
    static let iconSize: CGFloat = 18
}
