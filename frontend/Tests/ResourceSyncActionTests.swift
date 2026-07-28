import Foundation
import Testing
@testable import MHGLauncher

@Suite("游戏资料同步")
struct ResourceSyncActionTests {
    @Test("同步状态区分进行中与可用")
    func syncingState() {
        #expect(status("syncing").isSyncing)
        var assets = status("ready")
        assets.assetState = "syncing"
        #expect(assets.isSyncing)
        #expect(!status("ready").isSyncing)
    }

    @Test("首次启动等待完整资料缓存结束")
    @MainActor
    func initialSetupWaitsForAssets() async {
        let backend = InitialResourceBackend()
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })

        await store.prepareInitialResources()

        #expect(store.value.resourceSyncStatus?.initialInstallRequired == false)
        #expect(store.value.resourceSyncStatus?.assetCompleted == 8)
        #expect(store.resourceSetupError == nil)
    }

    @Test("首次资料下载失败可重试并继续启动")
    @MainActor
    func initialSetupRetries() async {
        let backend = InitialResourceBackend()
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })
        var initial = status("retry", error: "下载失败")
        initial.initialInstallRequired = true
        store.value.resourceSyncStatus = initial
        store.resourceSetupError = "下载失败"

        await store.retryInitialResources()

        #expect(await backend.sawSync())
        #expect(store.value.resourceSyncStatus?.initialInstallRequired == false)
        #expect(store.resourceSetupError == nil)
    }

    @Test("首次资料状态读取失败显示错误")
    @MainActor
    func initialSetupStatusFailure() async {
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { _ in throw URLError(.notConnectedToInternet) })

        await store.prepareInitialResources()

        #expect(store.resourceSetupError != nil)
    }

    @Test("同步失败恢复刷新前状态")
    @MainActor
    func failedSyncRestoresState() async {
        let backend = ResourceSyncBackend(failSync: true)
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })
        store.value.resourceSyncStatus = status("ready")
        store.value.gachaResourceStatus = gachaStatus

        await store.installGachaResources()

        #expect(store.value.resourceSyncStatus == status("ready"))
        #expect(store.value.gachaResourceStatus == gachaStatus)
        #expect(store.message != nil)
    }

    @Test("后端待重试原因展示给用户并保留旧资料")
    @MainActor
    func retryReasonIsPresented() async {
        let backend = ResourceSyncBackend(failSync: false)
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })

        await store.installGachaResources()

        #expect(store.value.resourceSyncStatus?.state == "retry")
        #expect(store.value.gachaResourceStatus?.isReady == true)
        #expect(store.message == "资料同步失败")
    }
}

private actor InitialResourceBackend {
    private var requests = 0
    private var synced = false

    func respond(_ request: APIRequest) throws -> APIResponse {
        let route = request.path.components(separatedBy: "?")[0]
        if request.method == "POST", route == "/v1/resources/sync" {
            synced = true
            return try response(completedStatus())
        }
        if route == "/v1/resources/status" {
            requests += 1
            if synced { return try response(completedStatus()) }
            var value = completedStatus()
            value.assetState = requests == 1 ? "syncing" : "ready"
            value.assetCompleted = requests == 1 ? 2 : 8
            value.initialInstallRequired = requests == 1
            return try response(value)
        }
        if route == "/v1/accounts" { return try response([Account]()) }
        if route == "/v1/account" { return APIResponse(status: 200, body: Data("null".utf8)) }
        if route == "/v1/roles" { return try response([GameRole]()) }
        if route == "/v1/notifications/settings" {
            return try response(NotificationSettings(
                dailyCommissionEnabled: false, dailyCommissionTime: "04:00",
                resinFullEnabled: false, gachaRefreshEnabled: false, versionUpdateEnabled: false
            ))
        }
        if route == "/v1/game/status" { return try response(InteractiveFixtures.gameState) }
        if route == "/v1/settings/speed-limit" {
            return try response(SpeedLimitResponse(speedLimitKb: 0))
        }
        return APIResponse(status: 404, body: Data())
    }

    func sawSync() -> Bool { synced }

    private func completedStatus() -> ResourceSyncStatus {
        var value = status("ready")
        value.assetState = "ready"; value.assetCompleted = 8; value.assetTotal = 8
        value.initialInstallRequired = false
        return value
    }
}

private actor ResourceSyncBackend {
    let failSync: Bool

    init(failSync: Bool) {
        self.failSync = failSync
    }

    func respond(_ request: APIRequest) throws -> APIResponse {
        let route = request.path.components(separatedBy: "?")[0]
        if route == "/v1/resources/sync" {
            if failSync {
                return APIResponse(
                    status: 502,
                    body: Data(#"{"code":"sync_failed","message":"资料同步失败","details":{}}"#.utf8)
                )
            }
            return try response(status("retry", error: "资料同步失败"))
        }
        if route == "/v1/gacha-resources/status" { return try response(gachaStatus) }
        if route == "/v1/gacha-events" { return try response([GachaEvent]()) }
        return APIResponse(status: 404, body: Data())
    }
}

private let gachaStatus = GachaResourceStatus(
    state: "ready", version: "old", eventCount: 1, imageCount: 1,
    installedBytes: 1, installedAt: nil
)

private func status(_ state: String, error: String? = nil) -> ResourceSyncStatus {
    ResourceSyncStatus(
        state: state, oid: "old", lastCheckedAt: nil, lastSuccessAt: nil,
        triggerGameVersion: nil, usingLegacyCache: true, error: error
    )
}

private func response<T: Encodable>(_ value: T) throws -> APIResponse {
    APIResponse(status: 200, body: try JSONEncoder.api.encode(value))
}
