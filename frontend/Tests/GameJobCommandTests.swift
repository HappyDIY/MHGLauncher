import Foundation
import Testing
@testable import MHGLauncher

@Suite("游戏任务严格请求契约", .serialized)
struct GameJobCommandTests {
    @Test("安装按钮只发送 install 任务")
    @MainActor
    func installButtonUsesInstallJob() async throws {
        try await assertStartsGameJob(.install)
    }

    @Test("更新按钮只发送 update 任务")
    @MainActor
    func updateButtonUsesUpdateJob() async throws {
        try await assertStartsGameJob(.update)
    }

    @Test("预下载按钮只发送 predownload 任务")
    @MainActor
    func predownloadButtonUsesPredownloadJob() async throws {
        try await assertStartsGameJob(.predownload)
    }

    @MainActor
    private func assertStartsGameJob(_ kind: JobKind) async throws {
        let installPath = InteractiveFixtures.gameState.installPath
        let jobBody = JSONValue.object([
            "kind": .string(kind.rawValue),
            "install_path": .string(installPath),
        ])
        let transport = ScriptedTransport([
            try .init(
                "GET", "/v1/game/status/path",
                query: ["install_path": installPath],
                response: InteractiveFixtures.gameState
            ),
            try .init(
                "GET", "/v1/game/space-check",
                query: ["install_path": installPath, "kind": kind.rawValue],
                response: SpaceCheckResult(available: 9_999, required: 1, sufficient: true)
            ),
            try .init(
                "POST", "/v1/game/jobs",
                body: jobBody,
                response: gameJob(.running, kind: kind)
            ),
            try .init(
                "GET", "/v1/game/jobs/job-1",
                query: ["after_revision": "1", "wait_ms": "2000"],
                response: gameJob(.completed, kind: kind)
            ),
            try .init(
                "GET", "/v1/game/status/path",
                query: ["install_path": installPath],
                response: InteractiveFixtures.gameState
            ),
        ])
        let client = APIClient(token: "fixture") { try await transport.respond($0) }
        let store = makeStore(client)

        await store.startGameJob(kind)

        #expect(store.gameJob?.status == .completed)
        try await transport.verify()
    }

    @MainActor
    private func makeStore(_ client: APIClient) -> LauncherStore {
        let suiteName = "GameJobCommandTests.\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        settings.removePersistentDomain(forName: suiteName)
        let store = LauncherStore(dependencies: LauncherDependencies(
            keychain: MemoryKeychainStore(),
            userSettings: settings
        ))
        store.backend.useClient(client)
        store.gameState = InteractiveFixtures.gameState
        store.installPath = InteractiveFixtures.gameState.installPath
        store.gameRuntimeReady = true
        return store
    }
}
