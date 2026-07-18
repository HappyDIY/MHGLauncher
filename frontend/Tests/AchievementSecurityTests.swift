import Foundation
import Testing
@testable import MHGLauncher

@Suite("成就并发保护")
struct AchievementSecurityTests {
    @Test("版本冲突后重载并重放用户修改")
    @MainActor
    func retriesConflictingSave() async {
        let backend = ConflictBackend()
        let store = LauncherStore(deviceOwnerAuthenticator: AchievementAuthenticator())
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })
        store.roles = [InteractiveFixtures.role]
        store.value.achievementArchives = [archive]
        store.value.achievementEntries = [entry]

        await store.saveAchievement(entry, checked: true)

        #expect(await backend.revisions() == [0, 1])
        #expect(await backend.currents() == [1, 1])
        #expect(store.value.achievementRevision == 2)
    }
}

@MainActor
private struct AchievementAuthenticator: DeviceOwnerAuthenticating {
    func authenticate(reason: String) async throws {}
}

private actor ConflictBackend {
    private var saves = 0
    private var received: [(Int, Int)] = []

    func respond(_ request: APIRequest) throws -> APIResponse {
        let route = request.path.components(separatedBy: "?")[0]
        switch (request.method, route) {
        case ("POST", "/v1/achievements"):
            let value = try JSONDecoder.api.decode(AchievementSaveRequest.self, from: request.body ?? Data())
            received.append((value.expectedRevision, value.items[0].current))
            saves += 1
            if saves == 1 {
                return APIResponse(status: 409, body: Data(#"{"code":"archive_revision_conflict","message":"conflict","details":{}}"#.utf8))
            }
            return try response(snapshot(revision: 2))
        case ("GET", "/v1/achievements/archive"):
            return try response(archive)
        case ("GET", "/v1/achievements/snapshot"):
            return try response(snapshot(revision: 1))
        default:
            return APIResponse(status: 404, body: Data())
        }
    }

    func revisions() -> [Int] { received.map(\.0) }
    func currents() -> [Int] { received.map(\.1) }
}

private let archive = AchievementArchive(
    id: InteractiveFixtures.role.uid, name: InteractiveFixtures.role.uid,
    selected: true, createdAt: .now, updatedAt: .now, revision: 0
)
private let entry = AchievementEntry(
    archiveId: InteractiveFixtures.role.uid, achievementId: 84501, current: 0, status: 0, timestamp: 0,
    updatedAt: "", goal: 1, order: 1, title: "成就", description: "", progress: 1,
    version: "1.0", rewardCount: 5, iconUrl: nil, isDailyQuest: false
)

private func snapshot(revision: Int) -> AchievementSnapshot {
    AchievementSnapshot(archive: archive, entries: [entry], revision: revision)
}

private func response<T: Encodable>(_ value: T) throws -> APIResponse {
    APIResponse(status: 200, body: try JSONEncoder.api.encode(value))
}
