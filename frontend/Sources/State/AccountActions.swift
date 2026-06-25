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
            let session: QRSession = try await client.post("/v1/auth/qr-sessions")
            qrSession = session
            try await pollQR(session.id, client: client)
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

    private func pollQR(_ id: String, client: APIClient) async throws {
        while !Task.isCancelled {
            let result: QRResult = try await client.get("/v1/auth/qr-sessions/\(id)")
            qrSession = result.session
            if result.session.status == "expired" {
                message = "二维码已过期，请重新生成"
                return
            }
            if let identity = result.identity {
                try keychain.save(identity.credential, account: keychainAccount(for: identity.aid))
                let request = LoginCompleteRequest(
                    identity: identity,
                    credentialRef: "keychain:\(keychainAccount(for: identity.aid))"
                )
                let response: LoginCompleteResponse = try await client.post(
                    "/v1/auth/complete",
                    body: request
                )
                account = response.account
                roles = response.roles
                accounts = try await client.get("/v1/accounts")
                qrSession = nil
                await loadCompanionData()
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
    }
}
