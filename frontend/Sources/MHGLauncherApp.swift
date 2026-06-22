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

            Divider()

            Button("同步记录") {
                Task { await store?.syncWishes() }
            }
            .disabled(store?.wishOperation != nil)

            Divider()

            Button("导入 UIGF 数据") {
                store?.selectedDestination = .wishes
                store?.triggerWishImport = true
            }

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

            Divider()

            if store?.account != nil {
                Button("退出登录") {
                    Task { await store?.logout() }
                }
            } else {
                Button("扫码登录") {
                    store?.selectedDestination = .account
                    Task { await store?.beginQRLogin() }
                }
            }
        }
    }
}

@main
struct MHGLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store: LauncherStore

    init() {
        let store = LauncherStore()
        _store = State(initialValue: store)
        if ProcessInfo.processInfo.environment["MHG_SMOKE_MODE"] == "1" {
            Task { @MainActor in await store.backend.start() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    await store.bootstrap()
                    await store.runNoteRefreshLoop()
                }
                .onDisappear { store.backend.stop() }
                .focusedSceneValue(\.launcherStore, store)
        }
        .windowStyle(.automatic)
        .commands {
            AppCommands()
        }
    }
}
