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
    @State private var selection: Destination? = .home

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { destination in
                Label(destination.rawValue, systemImage: destination.icon)
                    .tag(destination)
            }
            .navigationTitle("MHGLauncher")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            content
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
    }

    @ViewBuilder
    private var content: some View {
        switch selection ?? .home {
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
                Color.accentColor.opacity(0.12),
                Color.purple.opacity(0.08),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

