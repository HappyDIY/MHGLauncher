import Foundation
import Testing
@testable import MHGLauncher

@Suite("运行时安装界面")
struct RuntimeSetupPresentationTests {
    @Test("首次安装显示运行时安装界面")
    @MainActor
    func presentsSetupBeforeCoreRuntimeIsInstalled() throws {
        let fixture = try CoreFixture()
        let store = makeStore(installer: RuntimeInstaller(environment: fixture.environment))

        #expect(store.isInstallingCoreRuntime)
    }

    @Test("已安装运行时静默启动后端")
    @MainActor
    func startsInstalledRuntimeSilently() async throws {
        let fixture = try CoreFixture()
        let installer = RuntimeInstaller(environment: fixture.environment)
        _ = try await installer.ensureCore()

        let store = makeStore(installer: installer)

        #expect(!store.isInstallingCoreRuntime)
        #expect(!store.backend.isReady)
    }

    @MainActor
    private func makeStore(installer: RuntimeInstaller) -> LauncherStore {
        let suiteName = "RuntimeSetupPresentationTests.\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        settings.removePersistentDomain(forName: suiteName)
        return LauncherStore(dependencies: LauncherDependencies(
            runtimeInstaller: installer,
            keychain: MemoryKeychainStore(),
            userSettings: settings
        ))
    }
}
