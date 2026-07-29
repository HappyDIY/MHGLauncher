import Foundation
import Testing
@testable import MHGLauncher

@Suite("后台刷新")
struct BackgroundRefreshTests {
    @Test("自动刷新失败不弹出全局错误")
    @MainActor
    func silentFailuresDoNotPresentAlert() async throws {
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { _ in
            throw URLError(.timedOut)
        })
        store.account = Account(
            aid: "background-refresh",
            mid: "mid",
            nickname: "测试账号",
            credentialRef: "keychain:account:background-refresh",
            selected: true,
            updatedAt: .now
        )
        store.roles = [
            GameRole(
                uid: "100000001",
                nickname: "旅行者",
                region: "cn_gf01",
                level: 60,
                selected: true
            )
        ]
        let key = store.keychainAccount(for: "background-refresh")
        try store.keychain.save("stoken=fixture", account: key)
        defer { try? store.keychain.delete(account: key) }

        await store.refreshNote(silent: true)
        await store.evaluateNotifications(silent: true)

        #expect(store.message == nil)
        #expect(store.noteVerification == nil)
    }

    @Test("手动刷新失败仍显示错误")
    @MainActor
    func explicitFailurePresentsAlert() async {
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { _ in
            throw URLError(.timedOut)
        })

        await store.evaluateNotifications()

        #expect(store.message == "操作失败，请稍后重试")
    }

    @Test("自动便笺刷新不弹出验证或接口错误")
    @MainActor
    func silentNoteRefreshSuppressesProviderUI() async throws {
        let store = try authenticatedStore(response: APIResponse(
            status: 403,
            body: Data(
                #"{"code":"verification_required","message":"需要验证","details":{"gt":"gt","challenge":"challenge"}}"#.utf8
            )
        ))
        defer { try? store.keychain.delete(account: store.keychainAccount(for: "note-refresh")) }

        await store.refreshNote(silent: true)
        #expect(store.noteVerification == nil)

        await store.refreshNote()
        #expect(store.noteVerification?.challenge == "challenge")
    }

    @Test("手动便笺刷新仍显示接口错误")
    @MainActor
    func explicitNoteRefreshPresentsProviderError() async throws {
        let store = try authenticatedStore(response: APIResponse(
            status: 503,
            body: Data(#"{"code":"mihoyo_error","message":"上游失败","details":{}}"#.utf8)
        ))
        defer { try? store.keychain.delete(account: store.keychainAccount(for: "note-refresh")) }

        await store.refreshNote(silent: true)
        #expect(store.message == nil)

        await store.refreshNote()
        #expect(store.message == "米游社请求失败，请稍后重试")
    }

    @MainActor
    private func authenticatedStore(response: APIResponse) throws -> LauncherStore {
        let store = LauncherStore()
        store.backend.useClient(APIClient(token: "fixture") { _ in response })
        store.account = Account(
            aid: "note-refresh",
            mid: "mid",
            nickname: "测试账号",
            credentialRef: "keychain:account:note-refresh",
            selected: true,
            updatedAt: .now
        )
        try store.keychain.save(
            "stoken=fixture",
            account: store.keychainAccount(for: "note-refresh")
        )
        return store
    }
}
