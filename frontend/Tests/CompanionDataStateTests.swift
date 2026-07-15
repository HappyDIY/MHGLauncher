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

    @Test("迟到的角色详情不能反向选择旧角色")
    @MainActor
    func keepsLatestCharacterSelection() async {
        let backend = SlowCharacterBackend()
        let store = LauncherStore(deviceOwnerAuthenticator: CompanionAuthenticator())
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })
        store.account = InteractiveFixtures.account
        store.roles = [InteractiveFixtures.role]
        try! store.keychain.save("stoken=fixture", account: store.keychainAccount(for: InteractiveFixtures.account.aid))
        defer { try? store.keychain.delete(account: store.keychainAccount(for: InteractiveFixtures.account.aid)) }
        let first = character(id: "1001"), second = character(id: "1002")
        store.characters = [first, second]
        store.selectCharacter(first)

        let refresh = Task { await store.refreshCharacterDetail(first) }
        try? await Task.sleep(for: .milliseconds(20))
        store.selectCharacter(second)
        await refresh.value

        #expect(store.selectedCharacterId == second.avatarId)
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

private actor SlowCharacterBackend {
    func respond(_ request: APIRequest) async throws -> APIResponse {
        guard request.path == "/v1/characters/1001/refresh" else {
            return APIResponse(status: 404, body: Data())
        }
        try await Task.sleep(for: .milliseconds(80))
        return try json(character(id: "1001"))
    }
}

private func character(id: String) -> GameCharacter {
    GameCharacter(
        uid: InteractiveFixtures.role.uid, avatarId: id, name: "旅行者", element: "Anemo",
        level: 90, rarity: 5, constellation: 0, fetter: 10, weaponName: "剑",
        weaponLevel: 90, iconUrl: nil, payload: nil, updatedAt: .now
    )
}

private func json<T: Encodable>(_ value: T) throws -> APIResponse {
    APIResponse(status: 200, body: try JSONEncoder.api.encode(value))
}
