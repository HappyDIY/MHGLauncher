import Foundation
import Testing
@testable import MHGLauncher

@Suite("陪伴数据状态隔离")
struct CompanionDataStateTests {
    @Test("过期角色快照不能覆盖新选择")
    @MainActor
    func discardsStaleSnapshot() async {
        let backend = DelayedCompanionBackend()
        let store = LauncherStore(deviceOwnerAuthenticator: CompanionAuthenticator())
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })
        store.roles = [InteractiveFixtures.role]

        let load = Task { await store.loadCompanionData() }
        await backend.waitForRequest()
        _ = store.resetCompanionData()
        await backend.complete()
        await load.value

        #expect(store.wishes.isEmpty)
        #expect(!store.companionLoaded)
    }

    @Test("祈愿进行时拒绝第二个操作")
    @MainActor
    func rejectsConcurrentWishOperation() async {
        let store = LauncherStore(deviceOwnerAuthenticator: CompanionAuthenticator())
        let gate = OperationGate()
        let first = Task {
            await store.runWishOperation(.sync) {
                await gate.wait()
                throw CancellationError()
            }
        }
        await gate.waitForStart()
        var startedSecond = false
        await store.runWishOperation(.exportUIGF) { startedSecond = true }
        #expect(!startedSecond)
        await gate.release()
        await first.value
    }
}

@MainActor
private struct CompanionAuthenticator: DeviceOwnerAuthenticating {
    func authenticate(reason: String) async throws {}
}

private actor DelayedCompanionBackend {
    private var requested = false
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<APIResponse, Never>?

    func respond(_ request: APIRequest) async throws -> APIResponse {
        guard request.path.hasPrefix("/v1/companion/snapshot") else {
            return APIResponse(status: 404, body: Data())
        }
        requested = true
        requestWaiter?.resume()
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitForRequest() async {
        guard !requested else { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func complete() {
        let snapshot = CompanionSnapshot(wishes: [], statistics: [], bannerStatistics: [], note: nil)
        responseWaiter?.resume(returning: try! json(snapshot))
        responseWaiter = nil
    }
}

private actor OperationGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        startWaiter?.resume()
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForStart() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private func json<T: Encodable>(_ value: T) throws -> APIResponse {
    APIResponse(status: 200, body: try JSONEncoder.api.encode(value))
}
