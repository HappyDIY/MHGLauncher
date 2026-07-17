import Foundation
import Testing
@testable import MHGLauncher

@Suite("增值功能按钮业务逻辑")
struct AdditionalButtonBusinessActionTests {
    @Test("无关接口失败不阻止成就快照加载")
    @MainActor
    func achievementDomainLoadsIndependently() async {
        let backend = ValueFakeBackend(failureRoute: "/v1/gacha-events")
        let store = LauncherStore(deviceOwnerAuthenticator: ValueAuthenticator())
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })
        store.account = InteractiveFixtures.account
        store.roles = [InteractiveFixtures.role]

        await store.loadValueData()

        #expect(store.value.achievementLoaded)
        #expect(store.value.achievementError == nil)
        #expect(store.selectedAchievementArchive?.id == "archive-1")
    }

    @Test("卡池角色成就云端与通知按钮走完整契约")
    @MainActor
    func valueButtonsRunBusinessActions() async throws {
        let backend = ValueFakeBackend()
        let store = LauncherStore(deviceOwnerAuthenticator: ValueAuthenticator())
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })
        let account = Account(
            aid: "value-buttons", mid: "value-buttons", nickname: "旅行者",
            credentialRef: "keychain:account:value-buttons", selected: true, updatedAt: .now
        )
        store.account = account
        store.roles = [InteractiveFixtures.role]
        try store.keychain.save("stoken=fixture", account: store.keychainAccount(for: account.aid))
        defer {
            try? store.keychain.delete(account: store.keychainAccount(for: account.aid))
            try? store.keychain.delete(account: store.cloudKeychainAccount(uid: InteractiveFixtures.role.uid))
        }

        await store.loadValueData()
        #expect(store.value.gachaEvents.count == 1)
        #expect(store.characters.count == 1)
        #expect(store.value.achievementGoals.count == 1)
        #expect(store.selectedAchievementArchive?.id == "archive-1")

        await store.refreshGachaEvents()
        await store.refreshCharacters()
        await store.refreshSelectedCharacterDetail()
        await store.createAchievementArchive(named: "旅行档案")
        if let archive = store.selectedAchievementArchive { await store.selectAchievementArchive(archive) }
        if let entry = store.value.achievementEntries.first { await store.saveAchievement(entry, checked: true) }
        await store.updateNotificationSettings(settings, revertingTo: settings)
        await store.evaluateNotifications()
        await store.loginCloud()
        await store.uploadCloudWishes()
        await store.retrieveCloudWishes()

        #expect(store.message == nil)
        #expect(store.value.cloudMessage == "已取回 2 条记录")
        #expect(await backend.saw("POST", "/v1/gacha-events/refresh"))
        #expect(await backend.saw("POST", "/v1/characters/1001/refresh"))
        #expect(await backend.savedAchievementRevision == 0)
        #expect(await backend.saw("POST", "/v1/cloud/login/account"))
        #expect(await backend.saw("POST", "/v1/cloud/wishes/retrieve"))
    }

    @Test("提醒设置保存失败会恢复已确认状态")
    @MainActor
    func rollsBackFailedNotificationSave() async {
        let backend = ValueFakeBackend(failureRoute: "/v1/notifications/settings")
        let store = LauncherStore(deviceOwnerAuthenticator: ValueAuthenticator())
        store.backend.useClient(APIClient(token: "fixture") { try await backend.respond($0) })
        store.value.notificationSettings = settings
        var changed = settings
        changed.gachaRefreshEnabled = false
        store.value.notificationSettings = changed

        await store.updateNotificationSettings(changed, revertingTo: settings)

        #expect(store.value.notificationSettings == settings)
        #expect(store.value.notificationError != nil)
    }
}

@MainActor
private struct ValueAuthenticator: DeviceOwnerAuthenticating {
    func authenticate(reason: String) async throws {}
}

private actor ValueFakeBackend {
    private var requests: [APIRequest] = []
    private(set) var savedAchievementRevision: Int?
    private let failureRoute: String?

    init(failureRoute: String? = nil) { self.failureRoute = failureRoute }

    func respond(_ request: APIRequest) throws -> APIResponse {
        requests.append(request)
        let route = request.path.components(separatedBy: "?")[0]
        if route == failureRoute {
            return APIResponse(
                status: 500,
                body: Data(#"{"code":"fixture_failure","message":"fixture failed","details":{}}"#.utf8)
            )
        }
        switch (request.method, route) {
        case ("GET", "/v1/gacha-events"), ("POST", "/v1/gacha-events/refresh"): return try json([event])
        case ("GET", "/v1/characters"), ("POST", "/v1/characters/refresh"): return try json([character])
        case ("POST", "/v1/characters/1001/refresh"): return try json(character)
        case ("GET", "/v1/notifications/settings"), ("PUT", "/v1/notifications/settings"): return try json(settings)
        case ("POST", "/v1/notifications/evaluate"): return try json([NotificationEvent]())
        case ("GET", "/v1/achievements/goals"): return try json([goal])
        case ("GET", "/v1/achievements/archives"): return try json([archive])
        case ("GET", "/v1/achievements/snapshot"): return try json(snapshot)
        case ("POST", "/v1/achievements/archives"), ("POST", "/v1/achievements/archives/archive-1/select"): return try json(archive)
        case ("POST", "/v1/achievements"):
            savedAchievementRevision = try JSONDecoder.api.decode(AchievementSaveRequest.self, from: request.body ?? Data()).expectedRevision
            return try json(snapshot)
        case ("POST", "/v1/cloud/login/account"): return try json(CloudLoginResult(uid: InteractiveFixtures.role.uid, token: "cloud-token", tokenRef: "keychain:cloud", reverifiedAt: date))
        case ("POST", "/v1/cloud/wishes/upload"): return try json(CountResponse(inserted: nil, imported: nil, deleted: nil, uploaded: 2))
        case ("POST", "/v1/cloud/wishes/retrieve"): return try json(CountResponse(inserted: nil, imported: 2, deleted: nil, uploaded: nil))
        case ("GET", "/v1/companion/snapshot"): return try json(CompanionSnapshot(wishes: [], statistics: [], bannerStatistics: [], note: nil))
        default: return APIResponse(status: 500, body: Data(#"{"code":"missing","message":"missing route","details":{}}"#.utf8))
        }
    }

    func saw(_ method: String, _ route: String) -> Bool { requests.contains { $0.method == method && $0.path.components(separatedBy: "?")[0] == route } }
}

private let date = Date(timeIntervalSince1970: 1_782_144_000)
private let settings = NotificationSettings(dailyCommissionEnabled: true, dailyCommissionTime: "08:00", resinFullEnabled: true, gachaRefreshEnabled: true, versionUpdateEnabled: true)
private let event = GachaEvent(id: "event-1", version: "5.8", gachaType: "301", name: "卡池", startedAt: date, endedAt: date, orangeUp: ["角色"], purpleUp: [], bannerUrl: nil, updatedAt: date)
private let character = GameCharacter(uid: InteractiveFixtures.role.uid, avatarId: "1001", name: "旅行者", element: "Anemo", level: 90, rarity: 5, constellation: 0, fetter: 10, weaponName: "剑", weaponLevel: 90, iconUrl: nil, payload: nil, updatedAt: date)
private let archive = AchievementArchive(id: "archive-1", name: "默认", selected: true, createdAt: date, updatedAt: date, revision: 0)
private let goal = AchievementGoal(id: 1, order: 1, name: "天地万象", rewardCount: 5, iconUrl: nil)
private let entry = AchievementEntry(archiveId: "archive-1", achievementId: 1, current: 0, status: 0, timestamp: 0, updatedAt: "2026-07-01T00:00:00Z", goal: 1, order: 1, title: "起点", description: "完成测试", progress: 1, version: "1.0", rewardCount: 5, iconUrl: nil, isDailyQuest: false)
private let item = AchievementItem(archiveId: "archive-1", achievementId: 1, current: 1, status: 3, timestamp: 1, updatedAt: date)
private let snapshot = AchievementSnapshot(archive: archive, entries: [entry], revision: 0)

private func json<T: Encodable>(_ value: T) throws -> APIResponse { APIResponse(status: 200, body: try JSONEncoder.api.encode(value)) }
