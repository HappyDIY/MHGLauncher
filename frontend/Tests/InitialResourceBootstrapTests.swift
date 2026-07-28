import Foundation
import Testing
@testable import MHGLauncher

@Suite("首次资料启动流程")
struct InitialResourceBootstrapTests {
    @Test("资料完成后继续加载应用数据")
    @MainActor
    func continuesAfterMetadataIsReady() async throws {
        let backend = BootstrapResourceBackend(failsStatus: false)
        let store = try await makeStore(backend)

        await store.bootstrap()

        #expect(store.value.resourceSyncStatus?.initialInstallRequired == false)
        #expect(store.gameState != nil)
        #expect(!store.needsMetadataSetup)
    }

    @Test("资料状态读取失败时停留在重试界面")
    @MainActor
    func stopsWhenMetadataStatusFails() async throws {
        let backend = BootstrapResourceBackend(failsStatus: true)
        let store = try await makeStore(backend)

        await store.bootstrap()

        #expect(store.resourceSetupError != nil)
        #expect(store.gameState == nil)
        #expect(store.needsMetadataSetup)
    }

    @MainActor
    private func makeStore(_ service: BootstrapResourceBackend) async throws -> LauncherStore {
        let fixture = try CoreFixture()
        let installer = RuntimeInstaller(environment: fixture.environment)
        _ = try await installer.ensureCore()
        let backend = BackendProcess()
        backend.useClient(APIClient(token: "fixture") { try await service.respond($0) })
        let suite = "InitialResourceBootstrapTests.\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suite)!
        settings.removePersistentDomain(forName: suite)
        return LauncherStore(dependencies: LauncherDependencies(
            backend: backend,
            runtimeInstaller: installer,
            keychain: MemoryKeychainStore(),
            userSettings: settings
        ))
    }
}

private actor BootstrapResourceBackend {
    let failsStatus: Bool

    init(failsStatus: Bool) {
        self.failsStatus = failsStatus
    }

    func respond(_ request: APIRequest) throws -> APIResponse {
        let route = request.path.components(separatedBy: "?")[0]
        if route == "/v1/resources/status" {
            if failsStatus { throw URLError(.notConnectedToInternet) }
            return try encoded(resourceStatus())
        }
        if route == "/v1/accounts" { return try encoded([Account]()) }
        if route == "/v1/account" { return APIResponse(status: 200, body: Data("null".utf8)) }
        if route == "/v1/roles" { return try encoded([GameRole]()) }
        if route == "/v1/notifications/settings" {
            return try encoded(NotificationSettings(
                dailyCommissionEnabled: false, dailyCommissionTime: "04:00",
                resinFullEnabled: false, gachaRefreshEnabled: false, versionUpdateEnabled: false
            ))
        }
        if route == "/v1/game/status" { return try encoded(InteractiveFixtures.gameState) }
        if route == "/v1/settings/speed-limit" {
            return try encoded(SpeedLimitResponse(speedLimitKb: 0))
        }
        return APIResponse(status: 404, body: Data())
    }

    private func resourceStatus() -> ResourceSyncStatus {
        var status = ResourceSyncStatus(
            state: "ready", oid: "fixture", lastCheckedAt: nil, lastSuccessAt: nil,
            triggerGameVersion: nil, usingLegacyCache: false, error: nil
        )
        status.assetState = "ready"
        status.assetCompleted = 8
        status.assetTotal = 8
        status.initialInstallRequired = false
        return status
    }

    private func encoded<T: Encodable>(_ value: T) throws -> APIResponse {
        APIResponse(status: 200, body: try JSONEncoder.api.encode(value))
    }
}
