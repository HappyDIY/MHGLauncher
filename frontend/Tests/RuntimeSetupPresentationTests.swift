import Foundation
import SwiftUI
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

    @Test("首次资料下载界面显示进度与重试状态")
    @MainActor
    func metadataSetupProgress() throws {
        let store = LauncherStore()
        var status = ResourceSyncStatus(
            state: "ready", oid: "fixture", lastCheckedAt: nil, lastSuccessAt: nil,
            triggerGameVersion: nil, usingLegacyCache: false, error: nil
        )
        status.assetState = "syncing"; status.assetCompleted = 4; status.assetTotal = 8
        status.initialInstallRequired = true
        store.value.resourceSyncStatus = status
        #expect(ImageRenderer(content: MetadataSetupView(store: store)
            .frame(width: 800, height: 600)).nsImage != nil)
        store.startInitialResourceRetry()

        store.resourceSetupError = "资料下载失败"
        status.assetTotal = 0
        store.value.resourceSyncStatus = status
        #expect(ImageRenderer(content: MetadataSetupView(store: store)
            .frame(width: 800, height: 600)).nsImage != nil)
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
