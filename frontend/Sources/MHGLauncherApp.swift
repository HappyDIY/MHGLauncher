import SwiftUI

@main
struct MHGLauncherApp: App {
    @State private var store = LauncherStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .frame(minWidth: 980, minHeight: 680)
                .task { await store.bootstrap() }
                .onDisappear { store.backend.stop() }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

