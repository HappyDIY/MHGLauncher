import Foundation
import Testing
@testable import MHGLauncher

@Suite("游戏资料同步")
struct ResourceSyncActionTests {
    @Test("同步状态区分进行中与可用")
    func syncingState() {
        #expect(status("syncing").isSyncing)
        #expect(!status("ready").isSyncing)
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
