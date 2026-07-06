import Foundation
import Testing
@testable import MHGLauncher

@Suite("按钮业务逻辑")
struct ButtonBusinessActionTests {
    @Test("游戏页按钮执行业务流程")
    @MainActor
    func gameButtonsRunBusinessActions() async throws {
        let backend = ActionFakeBackend()
        let store = makeStore(backend: backend)

        await store.startGameJob(.install)
        #expect(store.gameJob?.status == .completed)
        await store.startGameJob(.update)
        await store.startGameJob(.predownload)
        let createdJob = await backend.saw("POST", "/v1/game/jobs")
        #expect(createdJob)

        store.gameJob = InteractiveFixtures.gameJob
        await store.controlGameJob("pause")
        #expect(store.gameJob?.status == .paused)
        await store.controlGameJob("resume")
        #expect(store.gameJob?.status == .running)
        await store.controlGameJob("cancel")
        #expect(store.gameJob?.status == .cancelled)

        await store.refreshSpeedLimit()
        await store.setSpeedLimit(2048)
        #expect(store.speedLimitKB == 2048)

        store.account = nil
        UserDefaults.standard.removeObject(forKey: store.loginDeferralKey)
        await store.launchGame()
        #expect(store.showsLoginBeforeLaunch)
        await store.deferLoginAndLaunch()
        let launched = await backend.saw("POST", "/v1/game/launch")
        #expect(launched)

        store.gameLaunch = InteractiveFixtures.gameLaunch
        await store.stopGame()
        #expect(store.gameLaunch?.status == .stopped)
    }

    @Test("账号页按钮执行业务流程")
    @MainActor
    func accountButtonsRunBusinessActions() async throws {
        let backend = ActionFakeBackend()
        let store = makeStore(backend: backend)
        defer { try? store.keychain.delete(account: store.keychainAccount(for: InteractiveFixtures.account.aid)) }

        await store.beginQRLogin()
        #expect(store.account?.aid == InteractiveFixtures.account.aid)
        #expect(!store.loginFormPresented)

        store.loginMobile = "13800138000"
        await store.sendMobileCaptcha()
        #expect(store.mobileCaptchaSession?.mobile == "13800138000")
        store.mobileCaptchaVerification = MobileCaptchaVerificationContext(
            mobile: store.loginMobile,
            verification: MobileCaptchaVerification(gt: "gt", challenge: "challenge", sessionId: "session")
        )
        await store.completeMobileCaptchaVerification(challenge: "c", validate: "v")
        #expect(store.mobileCaptchaVerification == nil)

        store.loginCaptcha = "123456"
        await store.loginByMobileCaptcha()
        #expect(store.loginCaptcha.isEmpty)
        store.loginCookie = "stoken=cookie; mid=mid"
        await store.loginByCookie()
        #expect(store.loginCookie.isEmpty)

        await store.selectAccount(InteractiveFixtures.account)
        await store.selectRole(InteractiveFixtures.role)
        #expect(store.selectedRole?.uid == InteractiveFixtures.role.uid)

        await store.logout()
        #expect(store.account == nil)
        #expect(store.roles.isEmpty)
        #expect(store.wishes.isEmpty)
    }

    @Test("祈愿与便笺按钮执行业务流程")
    @MainActor
    func wishAndNoteButtonsRunBusinessActions() async throws {
        let backend = ActionFakeBackend()
        let store = makeStore(backend: backend, authenticated: true)
        defer { try? store.keychain.delete(account: store.keychainAccount(for: InteractiveFixtures.account.aid)) }
        let root = try temporaryDirectory()

        await store.refreshNote()
        #expect(store.dailyNote?.uid == InteractiveFixtures.dailyNote.uid)
        store.noteVerification = GeetestChallenge(gt: "gt", challenge: "challenge")
        await store.completeNoteVerification(challenge: "c", validate: "v")
        #expect(store.noteVerification == nil)

        await store.syncWishes()
        #expect(store.wishes.count == InteractiveFixtures.wishRecords.count)

        let importURL = root.appending(path: "uigf-import.json")
        try Data(#"{"list":[]}"#.utf8).write(to: importURL)
        await store.importUIGF(from: importURL)
        let imported = await backend.saw("POST", "/v1/wishes/tasks/import")
        #expect(imported)

        let exportURL = root.appending(path: "uigf-export.json")
        await store.exportUIGF(to: exportURL)
        #expect(FileManager.default.fileExists(atPath: exportURL.path))

        await store.clearAllWishes()
        #expect(store.wishes.isEmpty)
        #expect(store.bannerDetails.isEmpty)
    }

    @MainActor
    private func makeStore(
        backend: ActionFakeBackend,
        authenticated: Bool = false
    ) -> LauncherStore {
        let store = LauncherStore(deviceOwnerAuthenticator: PassingAuthenticator())
        store.backend.useClient(APIClient(token: "fixture") { request in
            try await backend.respond(request)
        })
        store.account = InteractiveFixtures.account
        store.accounts = [InteractiveFixtures.account]
        store.roles = [InteractiveFixtures.role]
        store.gameState = InteractiveFixtures.gameState
        store.installPath = InteractiveFixtures.gameState.installPath
        store.gameRuntimeReady = true
        store.companionLoaded = true
        if authenticated {
            try? store.keychain.save(
                "stoken=fixture; mid=mid",
                account: store.keychainAccount(for: InteractiveFixtures.account.aid)
            )
        }
        return store
    }
}

@MainActor
private struct PassingAuthenticator: DeviceOwnerAuthenticating {
    func authenticate(reason: String) async throws {}
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
