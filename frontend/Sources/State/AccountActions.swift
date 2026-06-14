import Foundation

extension LauncherStore {
    func refreshAccount() async {
        await perform {
            let client = try requireClient()
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
            try await client.delete("/v1/account")
            try keychain.delete(account: credentialAccount)
            account = nil
            roles = []
            wishes = []
            wishStatistics = []
            bannerDetails = []
            dailyNote = nil
            qrSession = nil
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
                try keychain.save(identity.credential, account: credentialAccount)
                let request = LoginCompleteRequest(
                    identity: identity,
                    credentialRef: "keychain:\(credentialAccount)"
                )
                let response: LoginCompleteResponse = try await client.post(
                    "/v1/auth/complete",
                    body: request
                )
                account = response.account
                roles = response.roles
                qrSession = nil
                await loadCompanionData()
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
    }
}

