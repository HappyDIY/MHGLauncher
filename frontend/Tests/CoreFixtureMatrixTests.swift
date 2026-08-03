import Foundation
import Testing
@testable import MHGLauncher

@Suite("纯 Swift Fixture 功能矩阵", .serialized)
struct CoreFixtureMatrixTests {
    @Test("账号、资源、祈愿、便笺与游戏任务均通过类型化 Client")
    @MainActor
    func completeMatrix() async throws {
        let root = try tempDir()
        let host = LauncherCoreHost(
            environment: ["MHG_DATA_DIR": root.path, "MHG_PROVIDER_MODE": "fixture"],
            keychain: MemoryKeychainStore()
        )
        await host.start()
        let client = try #require(host.client)

        let qr = try await client.accounts.createQRSession()
        _ = try await client.accounts.queryQRSession(qr.id)
        let confirmed = try await client.accounts.queryQRSession(qr.id)
        let prepared = try #require(confirmed.preparedLogin)
        let login = try await client.accounts.commitLogin(prepared.transactionId)
        #expect(login.roles.first?.uid == "100000001")
        #expect((try await client.accounts.list()).count == 1)

        #expect((try await client.resources.sync(true)).state == "ready")
        #expect(try await client.resources.gachaStatus().state == "ready")
        let task = try await client.companion.startWishSync()
        var completed: WishTaskSnapshot?
        for try await event in client.companion.wishTaskEvents(task.id, task.revision) { completed = event }
        #expect(completed?.status == .completed)
        #expect(try await client.companion.snapshot("100000001").wishes.count == 2)
        #expect(try await client.companion.refreshNote(NoteRefreshRequest(
            xrpcChallenge: "", xrpcChallengePath: ""
        )).currentResin == 120)

        let game = root.appending(path: "fixture-game")
        let job = try await client.game.startJob(.install, game.path)
        var finished: GameJob?
        for try await event in client.game.jobEvents(job.id, job.revision) { finished = event }
        #expect(finished?.status == .completed)
        #expect(try await client.game.status(game.path).status == .ready)

        await host.stop()
        #expect(host.state == .stopped)
    }
}
