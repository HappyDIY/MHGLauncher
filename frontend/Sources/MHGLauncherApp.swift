import AppKit
import SwiftUI

struct LauncherStoreKey: FocusedValueKey {
    typealias Value = LauncherStore
}

extension FocusedValues {
    var launcherStore: LauncherStore? {
        get { self[LauncherStoreKey.self] }
        set { self[LauncherStoreKey.self] = newValue }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct AppCommands: Commands {
    @FocusedValue(\.launcherStore) private var store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .sidebar) {}

        CommandMenu("祈愿记录") {
            Button("打开祈愿记录") {
                store?.selectedDestination = .wishes
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(store == nil)

            Divider()

            Button("同步记录") {
                Task { await store?.syncWishes() }
            }
            .disabled(store.map { $0.wishOperation != nil || $0.selectedRole == nil } ?? true)

            Divider()

            Button("导入 UIGF 数据") {
                store?.selectedDestination = .wishes
                store?.triggerWishImport = true
            }
            .disabled(store?.selectedRole == nil)

            Button("导出 UIGF 数据") {
                store?.selectedDestination = .wishes
                store?.triggerWishExport = true
            }
            .disabled(store.map { $0.wishes.isEmpty } ?? true)

            Divider()

            Button("清空全部记录") {
                store?.selectedDestination = .wishes
                store?.triggerWishClear = true
            }
            .disabled(store.map { $0.wishes.isEmpty } ?? true)
        }

        CommandMenu("账号") {
            Button("打开账号管理") {
                store?.selectedDestination = .account
            }
            .keyboardShortcut("5", modifiers: .command)
            .disabled(store == nil)

            Divider()

            if let store, !store.accounts.isEmpty {
                Menu("切换账号") {
                    ForEach(store.accounts, id: \.aid) { account in
                        Button(account.displayName(role: nil)) {
                            Task { await store.selectAccount(account) }
                        }
                    }
                }
                if !store.roles.isEmpty {
                    Menu("切换角色") {
                        ForEach(store.roles) { role in
                            Button("\(role.nickname) · UID \(role.uid)") {
                                Task { await store.selectRole(role) }
                            }
                        }
                    }
                }
                Divider()
            }

            if store?.account != nil {
                Button("添加账号") {
                    store?.selectedDestination = .account
                    Task { await store?.beginAddingAccount() }
                }
                Button("退出登录") {
                    Task { await store?.logout() }
                }
            } else {
                Button("扫码登录") {
                    store?.selectedDestination = .account
                    Task { await store?.beginQRLogin() }
                }
                .disabled(store == nil)
            }
        }
    }
}

@main
struct MHGLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store: LauncherStore
    @State private var showsKeychainGuide: Bool
    @State private var didStart = false
    private let instanceGuard: SingleInstanceGuard?

    init() {
        let instanceGuard = SingleInstanceGuard.acquire()
        self.instanceGuard = instanceGuard
        _showsKeychainGuide = State(
            initialValue: instanceGuard != nil && KeychainAccessPrompt.shouldPresent()
        )
        let store = LauncherStore()
        _store = State(initialValue: store)
        guard instanceGuard != nil else {
            SingleInstanceGuard.activateExistingApplication()
            Task { @MainActor in NSApp.terminate(nil) }
            return
        }
    }

    var body: some Scene {
        WindowGroup {
            if instanceGuard == nil {
                EmptyView()
            } else if showsKeychainGuide {
                KeychainAccessGuideView(errorMessage: store.message) {
                    switch KeychainAccessPrompt.authorizeAfterGuide() {
                    case .success:
                        showsKeychainGuide = false
                        Task { await startLauncherIfNeeded() }
                    case .failure(let error):
                        store.message = LauncherStore.presentableMessage(
                            error.localizedDescription
                        )
                    }
                }
            } else {
                RootView(store: store)
                    .frame(width: 1150, height: 750)
                    .task {
                        await startLauncherIfNeeded()
                    }
                    .onDisappear { Task { await store.backend.stop() } }
                    .focusedSceneValue(\.launcherStore, store)
            }
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .commands {
            AppCommands()
        }
    }

    @MainActor
    private func startLauncherIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        store.showStatus("账号登录成功")
        await store.bootstrap()
        await store.runNoteRefreshLoop()
    }
}
