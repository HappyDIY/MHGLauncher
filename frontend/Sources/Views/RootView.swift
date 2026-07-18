import AppKit
import SwiftUI

struct RootView: View {
    @Bindable var store: LauncherStore
    @State private var confirmsClear = false

    var body: some View {
        Group {
            if showsRuntimeSetup {
                RuntimeSetupView(store: store)
            } else {
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
                    .scrollContentBackground(.hidden)
                    .background {
                        SidebarGlassEffect()
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
            }
        }
        .disabled(store.isWishOperationActive)
        .accessibilityHidden(store.isWishOperationActive)
        .overlay(alignment: .top) {
            if let status = store.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 18)
                    .motionTransition(.content)
                    .accessibilityIdentifier("launcher-status-message")
                    .accessibilityLiveRegion(.polite)
            }
        }
        .motionAnimation(.content, value: store.statusMessage)
        .overlay {
            WishOperationHost(store: store)
        }
        .motionAnimation(.emphasis, value: store.isWishOperationActive)
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
        .sheet(item: geetestSheet) { sheet in
            GeetestView(challenge: sheet.challenge, subtitle: sheet.subtitle) { value, validate in
                Task {
                    switch sheet {
                    case .note:
                        await store.completeNoteVerification(challenge: value, validate: validate)
                    case .mobile:
                        await store.completeMobileCaptchaVerification(challenge: value, validate: validate)
                    }
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
        .confirmationDialog(
            "建议先登录启动器账号",
            isPresented: $store.showsLoginBeforeLaunch,
            titleVisibility: .visible
        ) {
            Button("前往登录") {
                store.selectedDestination = .account
            }
            Button("本次直接启动") {
                Task { await store.deferLoginAndLaunch() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("登录后启动器会把账号透传给游戏，并可在启动器内切换账号和角色。多次跳过后将不再提示。")
        }
    }

    private var showsRuntimeSetup: Bool {
        !store.backend.isReady
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedDestination ?? .home {
        case .home: HomeView(store: store)
        case .game: GameView(store: store)
        case .wishes: WishesView(store: store)
        case .gachaHistory: GachaHistoryView(store: store)
        case .cloudSync: CloudSyncView(store: store)
        case .notes: NotesView(store: store)
        case .characters: CharactersView(store: store)
        case .achievements: AchievementsView(store: store)
        case .notifications: NotificationsView(store: store)
        case .account: AccountView(store: store)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                (store.selectedDestination ?? .home).accent.opacity(0.10),
                Color.primary.opacity(0.03),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .motionAnimation(.navigation, value: store.selectedDestination)
    }

    private var geetestSheet: Binding<GeetestSheet?> {
        Binding {
            if let verification = store.mobileCaptchaVerification {
                return .mobile(verification)
            }
            return store.noteVerification.map(GeetestSheet.note)
        } set: { value in
            if value == nil {
                store.mobileCaptchaVerification = nil
                store.noteVerification = nil
            }
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
