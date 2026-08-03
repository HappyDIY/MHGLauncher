import Foundation

extension LauncherStore {
    func commitPreparedLogin(_ prepared: PreparedLogin, client: LauncherClient) async throws {
        guard prepared.expiresAt > .now else {
            await abortPreparedLogin(prepared.transactionId, client: client)
            throw LauncherError.loginExpired
        }
        do {
            let response = try await client.accounts.commitLogin(prepared.transactionId)
            await acceptLogin(response, client: client)
        } catch {
            await abortPreparedLogin(prepared.transactionId, client: client)
            throw error
        }
    }

    func abortPreparedLogin(_ transactionId: String, client: LauncherClient) async {
        await client.accounts.abortLogin(transactionId)
    }

    private func acceptLogin(_ response: LoginCompleteResponse, client: LauncherClient) async {
        _ = startCompanionSelection()
        _ = resetCompanionData()
        account = response.account; roles = response.roles
        accounts = (try? await client.accounts.list()) ?? [response.account]
        loginFormPresented = false; clearLoginSecrets(); showStatus("账号登录成功")
        await loadCompanionData()
        await loadValueData()
    }

    func clearLoginSecrets() {
        loginMobile = ""; loginCaptcha = ""; loginCookie = ""
        mobileCaptchaSession = nil; mobileCaptchaVerification = nil
    }
}
