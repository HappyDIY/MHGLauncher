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
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try requireClient()
            mobileCaptchaSession = nil
            mobileCaptchaVerification = nil
            mobileCaptchaSession = try await client.post(
                "/v1/auth/mobile-captcha",
                body: MobileCaptchaRequest(mobile: loginMobile)
            )
            mobileCaptchaVerification = mobileCaptchaSession?.verification.map {
                MobileCaptchaVerificationContext(mobile: loginMobile, verification: $0)
            }
            message = "验证码已发送"
        } catch let error as APIErrorPayload {
            if error.code == "verification_required", let value = mobileVerification(from: error) {
                mobileCaptchaVerification = value
            } else {
                message = Self.presentableMessage(error.message)
            }
        } catch {
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    func completeMobileCaptchaVerification(challenge: String, validate: String) async {
        guard let verification = mobileCaptchaVerification else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try requireClient()
            mobileCaptchaSession = try await client.post(
                "/v1/auth/mobile-captcha/verification",
                body: MobileCaptchaVerificationRequest(
                    mobile: verification.mobile,
                    sessionId: verification.verification.sessionId,
                    challenge: challenge,
                    validate: validate
                )
            )
            mobileCaptchaVerification = nil
            message = "验证码已发送"
        } catch let error as APIErrorPayload {
            message = Self.presentableMessage(error.message)
        } catch {
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    func loginByMobileCaptcha() async {
        await perform {
            let client = try requireClient()
            guard let session = mobileCaptchaSession else { return }
            let request = MobileLoginRequest(
                mobile: session.mobile,
                captcha: loginCaptcha,
                actionType: session.actionType,
                aigis: session.aigis
            )
            let response: LoginCompleteResponse = try await client.post(
                "/v1/auth/mobile-login",
                body: request
            )
            try await acceptLogin(response, credential: response.identity?.credential, client: client)
            loginCaptcha = ""
        }
    }

    func loginByCookie() async {
        await perform {
            let client = try requireClient()
            let request = CookieLoginRequest(
                credential: loginCookie
            )
            let response: LoginCompleteResponse = try await client.post(
                "/v1/auth/cookie-login",
                body: request
            )
            try await acceptLogin(response, credential: loginCookie, client: client)
            loginCookie = ""
        }
    }

    func logout() async {
        await perform {
            let client = try requireClient()
            let oldAid = account?.aid
            try await client.delete("/v1/account")
            if let oldAid { try keychain.delete(account: keychainAccount(for: oldAid)) }
            accounts = try await client.get("/v1/accounts")
            account = try await client.get("/v1/account")
            roles = try await client.get("/v1/roles")
            wishes = []
            wishStatistics = []
            bannerDetails = []
            dailyNote = nil
            qrSession = nil
            loginFormPresented = false
            mobileCaptchaVerification = nil
        }
    }

    func selectAccount(_ value: Account) async {
        await perform {
            let client = try requireClient()
            let response: AccountSelectionResponse = try await client.post(
                "/v1/account/select",
                body: ["aid": value.aid]
            )
            account = response.account
            roles = response.roles
            accounts = try await client.get("/v1/accounts")
            await loadCompanionData()
        }
    }

    func selectRole(_ value: GameRole) async {
        await perform {
            let client = try requireClient()
            let selected: GameRole = try await client.post(
                "/v1/roles/select",
                body: ["uid": value.uid]
            )
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
        }
    }

    private func pollQR(_ id: String, attempt: Int, client: APIClient) async throws {
        while !Task.isCancelled {
            let result: QRResult = try await client.get("/v1/auth/qr-sessions/\(id)")
            guard applyQRSession(result.session, attempt: attempt) else { return }
            if result.session.status == "expired" {
                return
            }
            if let identity = result.identity {
                let request = LoginCompleteRequest(
                    identity: identity,
                    credentialRef: "keychain:\(keychainAccount(for: identity.aid))"
                )
                let response: LoginCompleteResponse = try await client.post(
                    "/v1/auth/complete",
                    body: request
                )
                try await acceptLogin(response, credential: identity.credential, client: client)
                finishQRLoginAttempt(attempt)
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    private func acceptLogin(
        _ response: LoginCompleteResponse,
        credential: String?,
        client: APIClient
    ) async throws {
        account = response.account
        roles = response.roles
        if let credential {
            try keychain.save(credential, account: keychainAccount(for: response.account.aid))
        }
        accounts = try await client.get("/v1/accounts")
        loginFormPresented = false
        showStatus("账号登录成功")
        await loadCompanionData()
    }
}
