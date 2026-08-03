import Foundation

extension LauncherStore {
    func refreshAccount() async {
        await perform {
            let client = try requireClient()
            accounts = try await client.accounts.list()
            account = try await client.accounts.selected()
            roles = try await client.accounts.roles()
        }
    }

    func beginQRLogin() async {
        await perform {
            let client = try requireClient()
            showAccountLogin()
            let attempt = startQRLoginAttempt()
            let session = try await client.accounts.createQRSession()
            guard applyQRSession(session, attempt: attempt) else { return }
            try await pollQR(session.id, attempt: attempt, client: client)
        }
    }

    func sendMobileCaptcha() async {
        let generation = startLoginGeneration()
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try requireClient()
            mobileCaptchaSession = nil
            mobileCaptchaVerification = nil
            let session = try await client.accounts.sendMobileCaptcha(loginMobile)
            guard isCurrentLoginGeneration(generation) else { return }
            mobileCaptchaSession = session
            mobileCaptchaVerification = mobileCaptchaSession?.verification.map {
                MobileCaptchaVerificationContext(mobile: loginMobile, verification: $0)
            }
            message = "验证码已发送"
        } catch let error as LauncherCoreError {
            if error.code == "verification_required", let value = mobileVerification(from: error) {
                mobileCaptchaVerification = value
            } else {
                message = Self.presentableMessage(error)
            }
        } catch {
            message = Self.presentableMessage(error)
        }
    }

    func completeMobileCaptchaVerification(challenge: String, validate: String) async {
        guard let verification = mobileCaptchaVerification else { return }
        let generation = loginGeneration
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try requireClient()
            let session = try await client.accounts.verifyMobileCaptcha(
                MobileCaptchaVerificationRequest(
                    mobile: verification.mobile,
                    sessionId: verification.verification.sessionId,
                    challenge: challenge,
                    validate: validate
                )
            )
            guard isCurrentLoginGeneration(generation) else { return }
            mobileCaptchaSession = session
            mobileCaptchaVerification = nil
            message = "验证码已发送"
        } catch let error as LauncherCoreError {
            message = Self.presentableMessage(error)
        } catch {
            message = Self.presentableMessage(error)
        }
    }

    func loginByMobileCaptcha() async {
        let generation = loginGeneration
        await perform {
            let client = try requireClient()
            guard let session = mobileCaptchaSession else { return }
            let request = MobileLoginRequest(
                mobile: session.mobile,
                captcha: loginCaptcha,
                actionType: session.actionType,
                aigis: session.aigis
            )
            let prepared = try await client.accounts.prepareMobileLogin(request)
            guard isCurrentLoginGeneration(generation) else { await abortPreparedLogin(prepared.transactionId, client: client); return }
            try await commitPreparedLogin(prepared, client: client)
        }
    }

    func loginByCookie() async {
        let generation = startLoginGeneration()
        await perform {
            let client = try requireClient()
            let prepared = try await client.accounts.prepareCookieLogin(loginCookie)
            guard isCurrentLoginGeneration(generation) else { await abortPreparedLogin(prepared.transactionId, client: client); return }
            try await commitPreparedLogin(prepared, client: client)
        }
    }

    func logout() async {
        _ = startLoginGeneration()
        _ = startCompanionSelection()
        _ = resetCompanionData()
        await perform {
            let client = try requireClient()
            try await client.accounts.logout()
            accounts = try await client.accounts.list()
            account = try await client.accounts.selected()
            roles = try await client.accounts.roles()
            qrSession = nil
            loginFormPresented = false
            mobileCaptchaVerification = nil
            clearLoginSecrets()
        }
    }

    func selectAccount(_ value: Account) async {
        let intent = startCompanionSelection()
        await perform {
            let client = try requireClient()
            let response = try await client.accounts.selectAccount(value.aid)
            guard isCurrentCompanionSelection(intent) else { return }
            _ = resetCompanionData()
            account = response.account
            roles = response.roles
            accounts = try await client.accounts.list()
            guard isCurrentCompanionSelection(intent) else { return }
            await loadCompanionData()
            await loadValueData()
        }
    }

    func selectRole(_ value: GameRole) async {
        let intent = startCompanionSelection()
        await perform {
            let client = try requireClient()
            let selected = try await client.accounts.selectRole(value.uid)
            guard isCurrentCompanionSelection(intent) else { return }
            _ = resetCompanionData()
            roles = roles.map { role in
                GameRole(
                    uid: role.uid,
                    nickname: role.nickname,
                    region: role.region,
                    level: role.level,
                    selected: role.uid == selected.uid
                )
            }
            await loadCompanionData()
            await loadValueData()
        }
    }

    private func pollQR(_ id: String, attempt: Int, client: LauncherClient) async throws {
        while !Task.isCancelled {
            let result = try await client.accounts.queryQRSession(id)
            guard applyQRSession(result.session, attempt: attempt) else {
                if let prepared = result.preparedLogin { await abortPreparedLogin(prepared.transactionId, client: client) }
                return
            }
            if result.session.status == "expired" {
                return
            }
            if let prepared = result.preparedLogin {
                guard attempt == qrLoginAttempt else { await abortPreparedLogin(prepared.transactionId, client: client); return }
                try await commitPreparedLogin(prepared, client: client)
                finishQRLoginAttempt(attempt)
                return
            }
            try await clock.sleep(for: .seconds(2))
        }
    }

}
