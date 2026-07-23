import Foundation

extension LauncherStore {
    func refreshAccount() async {
        await perform {
            let client = try requireClient()
            accounts = try await client.get("/v1/accounts")
            account = try await client.get("/v1/account")
            roles = try await client.get("/v1/roles")
        }
    }

    func beginQRLogin() async {
        await perform {
            let client = try requireClient()
            showAccountLogin()
            let attempt = startQRLoginAttempt()
            let session: QRSession = try await client.post("/v1/auth/qr-sessions")
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
            let session: MobileCaptchaSession = try await client.post(
                "/v1/auth/mobile-captcha",
                body: MobileCaptchaRequest(mobile: loginMobile)
            )
            guard isCurrentLoginGeneration(generation) else { return }
            mobileCaptchaSession = session
            mobileCaptchaVerification = mobileCaptchaSession?.verification.map {
                MobileCaptchaVerificationContext(mobile: loginMobile, verification: $0)
            }
            message = "验证码已发送"
        } catch let error as APIErrorPayload {
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
            let session: MobileCaptchaSession = try await client.post(
                "/v1/auth/mobile-captcha/verification",
                body: MobileCaptchaVerificationRequest(
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
        } catch let error as APIErrorPayload {
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
            let prepared: PreparedLogin = try await client.post(
                "/v1/auth/mobile-login",
                body: request
            )
            guard isCurrentLoginGeneration(generation) else { await abortPreparedLogin(prepared.transactionId, client: client); return }
            try await commitPreparedLogin(prepared, client: client)
        }
    }

    func loginByCookie() async {
        let generation = startLoginGeneration()
        await perform {
            let client = try requireClient()
            let request = CookieLoginRequest(
                credential: loginCookie
            )
            let prepared: PreparedLogin = try await client.post(
                "/v1/auth/cookie-login",
                body: request
            )
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
            let oldAid = account?.aid
            let key = oldAid.map { keychainAccount(for: $0) }, previous = try key.flatMap { try keychain.read(account: $0) }
            if let key { try keychain.delete(account: key) }
            do { try await client.delete("/v1/account") }
            catch { if let key, let previous { try? keychain.save(previous, account: key) }; throw error }
            accounts = try await client.get("/v1/accounts")
            account = try await client.get("/v1/account")
            roles = try await client.get("/v1/roles")
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
            let response: AccountSelectionResponse = try await client.post(
                "/v1/account/select",
                body: ["aid": value.aid]
            )
            guard isCurrentCompanionSelection(intent) else { return }
            _ = resetCompanionData()
            account = response.account
            roles = response.roles
            accounts = try await client.get("/v1/accounts")
            guard isCurrentCompanionSelection(intent) else { return }
            await loadCompanionData()
            await loadValueData()
        }
    }

    func selectRole(_ value: GameRole) async {
        let intent = startCompanionSelection()
        await perform {
            let client = try requireClient()
            let selected: GameRole = try await client.post(
                "/v1/roles/select",
                body: ["uid": value.uid]
            )
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

    private func pollQR(_ id: String, attempt: Int, client: APIClient) async throws {
        while !Task.isCancelled {
            let result: QRResult = try await client.get("/v1/auth/qr-sessions/\(id)")
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
