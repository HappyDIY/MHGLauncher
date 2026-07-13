import Foundation

extension LauncherStore {
    func commitPreparedLogin(_ prepared: PreparedLogin, client: APIClient) async throws {
        guard prepared.expiresAt > .now else {
            await abortPreparedLogin(prepared.transactionId, client: client)
            throw LauncherError.loginExpired
        }
        let accountKey = keychainAccount(for: prepared.identity.aid)
        let previous = try keychain.read(account: accountKey)
        do {
            try keychain.save(prepared.identity.credential, account: accountKey)
            let response: LoginCompleteResponse = try await client.post(
                "/v1/auth/commit", body: LoginCommitRequest(transactionId: prepared.transactionId)
            )
            await acceptLogin(response, client: client)
        } catch {
            if let previous { try? keychain.save(previous, account: accountKey) }
            else { try? keychain.delete(account: accountKey) }
            await abortPreparedLogin(prepared.transactionId, client: client)
            throw error
        }
    }

    func abortPreparedLogin(_ transactionId: String, client: APIClient) async {
        let _: EmptyResponse? = try? await client.post(
            "/v1/auth/abort", body: LoginCommitRequest(transactionId: transactionId)
        )
    }

    private func acceptLogin(_ response: LoginCompleteResponse, client: APIClient) async {
        account = response.account; roles = response.roles
        accounts = (try? await client.get("/v1/accounts")) ?? [response.account]
        loginFormPresented = false; clearLoginSecrets(); showStatus("账号登录成功")
        await loadCompanionData()
    }

    func clearLoginSecrets() {
        loginMobile = ""; loginCaptcha = ""; loginCookie = ""
        mobileCaptchaSession = nil; mobileCaptchaVerification = nil
    }
}
