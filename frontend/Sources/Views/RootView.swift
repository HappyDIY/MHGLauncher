import AppKit
import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case home = "主页"
    case game = "游戏"
    case wishes = "祈愿记录"
    case notes = "实时便笺"
    case account = "账号"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .game: "gamecontroller"
        case .wishes: "sparkles"
        case .notes: "note.text"
        case .account: "person.crop.circle"
        }
    }
}

struct RootView: View {
    @Bindable var store: LauncherStore
    @State private var confirmsClear = false

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $store.selectedDestination) { destination in
                Label {
                    Text(destination.rawValue)
                } icon: {
                    Image(systemName: destination.icon)
                        .motionSymbolBounce(
                            value: store.selectedDestination == destination
                        )
                }
                    .tag(destination)
            }
            .navigationTitle("MHGLauncher")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            ZStack {
                content
                    .id(store.selectedDestination ?? .home)
                    .motionTransition(.navigation)
            }
            .motionAnimation(.navigation, value: store.selectedDestination)
            .padding(24)
            .background(background)
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { store.message != nil },
                set: { if !$0 { store.message = nil } }
            )
        ) {
            Button("好") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
        .environment(\.apiClient, store.backend.client)
        .sheet(item: $store.noteVerification) { challenge in
            GeetestView(challenge: challenge) { value, validate in
                Task {
                    await store.completeNoteVerification(
                        challenge: value,
                        validate: validate
                    )
                }
            }
        }
        .onChange(of: store.triggerWishImport) { _, newValue in
            guard newValue else { return }
            store.triggerWishImport = false
            importFile()
        }
        .onChange(of: store.triggerWishExport) { _, newValue in
            guard newValue else { return }
            store.triggerWishExport = false
            exportFile()
        }
        .onChange(of: store.triggerWishClear) { _, newValue in
            guard newValue else { return }
            store.triggerWishClear = false
            confirmsClear = true
        }
        .confirmationDialog(
            "永久清空全部祈愿记录？",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("认证并清空", role: .destructive) {
                Task { await store.clearAllWishes() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销，继续后需要使用 Touch ID 或 Mac 登录密码确认。")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedDestination ?? .home {
        case .home: HomeView(store: store)
        case .game: GameView(store: store)
        case .wishes: WishesView(store: store)
        case .notes: NotesView(store: store)
        case .account: AccountView(store: store)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                destinationAccent.opacity(0.12),
                Color.purple.opacity(0.08),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .motionAnimation(.navigation, value: store.selectedDestination)
    }

    private var destinationAccent: Color {
        switch store.selectedDestination ?? .home {
        case .home: .blue
        case .game: .indigo
        case .wishes: .cyan
        case .notes: .green
        case .account: .orange
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.importUIGF(from: url) }
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "uigf-v4.2.json"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.exportUIGF(to: url) }
        }
    }
}
