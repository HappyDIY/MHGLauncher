import Foundation
import Testing
@testable import MHGLauncher

@MainActor
@Suite("账号登录状态")
struct AccountLoginStateTests {
    @Test("已登录账号添加账号会显示登录表单并生成二维码")
    func addAccountShowsLoginForm() async {
        let store = LauncherStore()
        store.account = sampleAccount()
        store.backend.useClient(APIClient(token: "token") { request in
            if request.path == "/v1/auth/qr-sessions" {
                return json(200, """
                {"id":"qr-1","url":"https://example.invalid/qr","status":"created","expires_at":"2026-06-25T08:00:00Z"}
                """)
            }
            return json(200, """
            {"session":{"id":"qr-1","url":"https://example.invalid/qr","status":"expired","expires_at":"2026-06-25T08:00:00Z"},"identity":null}
            """)
        })

        await store.beginAddingAccount()
        #expect(store.loginFormPresented)
        #expect(store.qrSession?.status == "expired")
        #expect(store.message == nil)
    }

    @Test("短信风控弹出 Geetest，验证后自动重发验证码")
    func mobileCaptchaVerificationResends() async {
        let transport = CaptchaTransport()
        let store = LauncherStore()
        store.loginMobile = "13800138000"
        store.backend.useClient(APIClient(token: "token") { request in
            try await transport.response(for: request)
        })

        await store.sendMobileCaptcha()
        #expect(store.mobileCaptchaVerification?.verification.sessionId == "risk-session")
        await store.completeMobileCaptchaVerification(challenge: "client-challenge", validate: "validate-token")
        #expect(store.mobileCaptchaVerification == nil)
        #expect(store.mobileCaptchaSession?.aigis == "verified-aigis")
        #expect(store.message == "验证码已发送")
        let request = await transport.verification
        #expect(request?.mobile == "13800138000")
        #expect(request?.sessionId == "risk-session")
        #expect(request?.challenge == "client-challenge")
        #expect(request?.validate == "validate-token")
    }

    @Test("登录成功显示短暂状态")
    func loginSuccessShowsStatus() async throws {
        let store = LauncherStore()
        let aid = "test-\(UUID().uuidString)"
        store.loginCookie = "login_ticket=temporary-ticket"
        defer { try? store.keychain.delete(account: store.keychainAccount(for: aid)) }
        store.backend.useClient(APIClient(token: "token") { request in
            if request.path == "/v1/auth/cookie-login" {
                return json(200, preparedResponse(aid: aid, credential: "stoken=normalized-secret"))
            }
            if request.path == "/v1/auth/commit" {
                return json(200, loginResponse(aid: aid))
            }
            if request.path == "/v1/accounts" {
                return json(200, "[\(accountJSON(aid: aid))]")
            }
            return json(200, "[]")
        })

        await store.loginByCookie()
        #expect(store.statusMessage == "账号登录成功")
        #expect(store.loginFormPresented == false)
        #expect(try store.keychain.read(account: store.keychainAccount(for: aid)) == "stoken=normalized-secret")
    }

    @Test("commit 失败会恢复旧钥匙串凭据并撤销事务")
    func failedCommitRollsBackKeychain() async throws {
        let aid = "rollback-\(UUID().uuidString)", transport = PreparedTransport(aid: aid)
        let store = LauncherStore(); store.loginCookie = "login_ticket=temporary"
        let key = store.keychainAccount(for: aid); try store.keychain.save("stoken=old", account: key)
        defer { try? store.keychain.delete(account: key) }
        store.backend.useClient(APIClient(token: "token") { try await transport.response(for: $0) })
        await store.loginByCookie()
        #expect(try store.keychain.read(account: key) == "stoken=old")
        #expect(await transport.aborted)
    }

    @Test("二维码成功后旧过期响应不会覆盖账号状态")
    func staleExpiredDoesNotClearAccount() {
        let store = LauncherStore()
        store.account = sampleAccount()
        let attempt = store.startQRLoginAttempt()
        #expect(store.applyQRSession(qr(status: "created"), attempt: attempt))
        store.finishQRLoginAttempt(attempt)

        #expect(!store.applyQRSession(qr(status: "expired"), attempt: attempt))
        #expect(store.account?.aid == "1001")
        #expect(store.qrSession == nil)
        #expect(store.message == nil)
    }
}

private actor PreparedTransport {
    let aid: String; var aborted = false
    init(aid: String) { self.aid = aid }
    func response(for request: APIRequest) throws -> APIResponse {
        if request.path == "/v1/auth/cookie-login" { return json(200, preparedResponse(aid: aid, credential: "stoken=new")) }
        if request.path == "/v1/auth/abort" { aborted = true; return json(200, "{}") }
        return json(500, #"{"code":"commit_failed","message":"提交失败","details":{}}"#)
    }
}

private actor CaptchaTransport {
    var verification: MobileCaptchaVerificationRequest?

    func response(for request: APIRequest) async throws -> APIResponse {
        if request.path == "/v1/auth/mobile-captcha" {
            return json(428, """
            {"code":"verification_required","message":"请完成人机验证后重试","details":{"gt":"gt-token","challenge":"server-challenge","session_id":"risk-session"}}
            """)
        }
        verification = try JSONDecoder.api.decode(
            MobileCaptchaVerificationRequest.self,
            from: request.body ?? Data()
        )
        return json(200, """
        {"mobile":"13800138000","action_type":"login","countdown":60,"aigis":"verified-aigis"}
        """)
    }
}

private func sampleAccount() -> Account {
    Account(
        aid: "1001",
        mid: "mid-1",
        nickname: "旅行者",
        credentialRef: "keychain:account:1001",
        selected: true,
        updatedAt: .now
    )
}

private func qr(status: String) -> QRSession {
    QRSession(
        id: "qr-1",
        url: "https://example.invalid/qr",
        status: status,
        expiresAt: .now
    )
}

private func json(_ status: Int, _ body: String) -> APIResponse {
    APIResponse(status: status, body: Data(body.utf8))
}

private func preparedResponse(aid: String, credential: String) -> String {
    """
    {"transaction_id":"00000000-0000-4000-8000-000000000001","identity":{"aid":"\(aid)","mid":"mid","nickname":"旅行者","credential":"\(credential)"},"roles":[],"expires_at":"2099-06-25T08:00:00Z"}
    """
}

private func loginResponse(aid: String) -> String {
    """
    {"account":\(accountJSON(aid: aid)),"roles":[]}
    """
}

private func accountJSON(aid: String) -> String {
    """
    {"aid":"\(aid)","mid":"mid","nickname":"旅行者","credential_ref":"keychain:account:\(aid)","selected":true,"updated_at":"2026-06-25T08:00:00Z"}
    """
}
