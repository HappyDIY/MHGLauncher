import Foundation
import GRDB

actor CoreCloudService {
    private struct GachaAuthRequest: Encodable { let gachaUrl: String }
    private struct EmptyRequest: Encodable {}
    private struct EmptyResponse: Decodable {}
    private struct IdentityResponse: Decodable { let uid: String }
    private struct CountPayload: Decodable {
        let inserted: Int?
        let imported: Int?
        let uploaded: Int?
        let deleted: Int?
    }
    private struct WishesPayload: Decodable { let items: [CloudWish] }
    private struct WishUpload: Encodable { let items: [CloudWish] }
    private struct AchievementUpload: Encodable { let items: [CloudAchievement] }
    private struct AchievementsPayload: Decodable { let items: [CloudAchievement] }
    private struct CloudWish: Codable {
        let id: String
        let uid: String
        let gachaType: String
        let uigfGachaType: String
        let itemId: String
        let name: String
        let itemType: String
        let rank: Int
        let time: Date

        init(_ value: WishRecord) {
            id = value.id; uid = value.uid; gachaType = value.gachaType
            uigfGachaType = value.uigfGachaType ?? (value.gachaType == "400" ? "301" : value.gachaType)
            itemId = value.itemId; name = value.name; itemType = value.itemType
            rank = value.rank; time = value.time
        }

        var record: WishRecord {
            WishRecord(
                id: id, uid: uid, gachaType: gachaType, uigfGachaType: uigfGachaType, itemId: itemId,
                name: name, itemType: itemType, rank: rank, time: time, iconUrl: nil
            )
        }
    }
    private struct CloudAchievement: Codable {
        let achievementId: Int
        let current: Int
        let status: Int
        let timestamp: Int

        init(_ value: AchievementItemInput) {
            achievementId = value.achievementId
            current = value.current
            status = value.status
            timestamp = value.timestamp
        }

        var input: AchievementItemInput {
            AchievementItemInput(
                achievementId: achievementId,
                current: current,
                status: status,
                timestamp: timestamp
            )
        }
    }

    private let database: CoreDatabase
    private let accounts: CoreAccountService
    private let provider: any GameProvider
    private let wishes: CoreWishService
    private let achievements: CoreAchievementService
    private let keychain: any KeychainStoring
    private let transport: any HTTPTransport
    private let baseURL: URL?
    private let dataDirectory: URL
    private let fixtureMode: Bool

    init(
        database: CoreDatabase,
        accounts: CoreAccountService,
        provider: any GameProvider,
        wishes: CoreWishService,
        achievements: CoreAchievementService,
        keychain: any KeychainStoring,
        transport: any HTTPTransport,
        baseURL: URL?,
        dataDirectory: URL,
        fixtureMode: Bool
    ) {
        self.database = database
        self.accounts = accounts
        self.provider = provider
        self.wishes = wishes
        self.achievements = achievements
        self.keychain = keychain
        self.transport = transport
        self.baseURL = baseURL
        self.dataDirectory = dataDirectory
        self.fixtureMode = fixtureMode
    }

    func session(uid: String) async throws -> CloudSession? {
        guard Self.validUID(uid) else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        return try await database.read { db -> CloudSession? in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM cloud_sessions WHERE uid=?",
                arguments: [uid]
            ).map { row in
                CloudSession(
                    uid: row["uid"],
                    tokenRef: row["token_ref"],
                    reverifiedAt: CoreDate.parse(row["reverified_at"]),
                    updatedAt: CoreDate.parse(row["updated_at"])
                )
            }.flatMap { value in
                guard Self.validUID(value.uid), value.uid == uid,
                      value.tokenRef == "keychain:cloud:\(value.uid)",
                      value.reverifiedAt.timeIntervalSince1970.isFinite,
                      value.updatedAt.timeIntervalSince1970.isFinite else { return nil }
                return value
            }
        }
    }

    func login() async throws -> CloudLoginResult {
        guard let role = try await accounts.selectedRole() else {
            throw LauncherCoreError(code: "role_missing", message: "尚未选择游戏角色")
        }
        if fixtureMode {
            let credential = CloudCredentialResponse(
                uid: role.uid,
                token: "fixture-cloud-token",
                tokenRef: "keychain:cloud:\(role.uid)",
                reverifiedAt: Date()
            )
            try await save(credential)
            return CloudLoginResult(
                uid: credential.uid,
                tokenRef: credential.tokenRef,
                reverifiedAt: credential.reverifiedAt
            )
        }
        let url = try await provider.gachaURL(
            credential: try await accounts.credential(),
            role: role
        )
        return try await login(gachaURL: url, expectedUID: role.uid)
    }

    func login(gachaURL: URL, expectedUID: String? = nil) async throws -> CloudLoginResult {
        guard let normalized = MiHoYoSigning.normalizedGachaURL(gachaURL) else {
            throw LauncherCoreError(code: "gacha_url_invalid", message: "抽卡 URL 无效")
        }
        let credential: CloudCredentialResponse
        if fixtureMode {
            credential = CloudCredentialResponse(
                uid: expectedUID ?? "100000001",
                token: "fixture-cloud-token",
                tokenRef: "keychain:cloud:\(expectedUID ?? "100000001")",
                reverifiedAt: Date()
            )
        } else {
            credential = try await remote(
                path: "api/v1/auth/gacha-url",
                method: "POST",
                token: nil,
                body: GachaAuthRequest(gachaUrl: normalized.absoluteString),
                as: CloudCredentialResponse.self
            )
        }
        if let expectedUID, credential.uid != expectedUID {
            throw LauncherCoreError(
                code: "cloud_identity_mismatch",
                message: "云端鉴权 UID 与当前角色不匹配"
            )
        }
        try await save(credential)
        return CloudLoginResult(
            uid: credential.uid,
            tokenRef: credential.tokenRef,
            reverifiedAt: credential.reverifiedAt
        )
    }

    func reverify(gachaURL: URL, uid: String) async throws -> CloudLoginResult {
        guard Self.validUID(uid), let normalized = MiHoYoSigning.normalizedGachaURL(gachaURL) else {
            throw LauncherCoreError(code: "gacha_url_invalid", message: "抽卡 URL 无效")
        }
        let token = try cloudToken(uid: uid)
        if fixtureMode {
            guard let value = try await session(uid: uid) else {
                throw LauncherCoreError(code: "credential_missing", message: "云同步凭据不可用，请重新登录")
            }
            return CloudLoginResult(uid: value.uid, tokenRef: value.tokenRef, reverifiedAt: value.reverifiedAt)
        }
        let credential: CloudCredentialResponse = try await remote(
            path: "api/v1/auth/reverify",
            method: "POST",
            token: token,
            body: GachaAuthRequest(gachaUrl: normalized.absoluteString),
            as: CloudCredentialResponse.self
        )
        guard credential.uid == uid else {
            throw LauncherCoreError(code: "cloud_identity_mismatch", message: "云端会话与角色 UID 不匹配")
        }
        try await save(credential)
        return CloudLoginResult(
            uid: credential.uid,
            tokenRef: credential.tokenRef,
            reverifiedAt: credential.reverifiedAt
        )
    }

    func uploadWishes(uid: String) async throws -> Int {
        let token = try cloudToken(uid: uid)
        if fixtureMode { return try await wishes.list(uid: uid).count }
        try await assertIdentity(uid: uid, token: token)
        let payload: CountPayload = try await remote(
            path: "api/v1/gacha/upload",
            method: "POST",
            token: token,
            body: WishUpload(items: try await wishes.list(uid: uid).map(CloudWish.init)),
            as: CountPayload.self
        )
        return try count(from: payload)
    }

    func retrieveWishes(uid: String) async throws -> Int {
        let token = try cloudToken(uid: uid)
        if fixtureMode { return 0 }
        try await assertIdentity(uid: uid, token: token)
        let payload: WishesPayload = try await remote(
            path: "api/v1/gacha/retrieve",
            method: "POST",
            token: token,
            body: EmptyRequest(),
            as: WishesPayload.self
        )
        guard payload.items.allSatisfy({ $0.uid == uid }) else {
            throw LauncherCoreError(code: "cloud_identity_mismatch", message: "云端祈愿数据与角色 UID 不匹配")
        }
        _ = try await wishes.importCloud(payload.items.map(\.record))
        return payload.items.count
    }

    func uploadAchievements(uid: String) async throws -> Int {
        let token = try cloudToken(uid: uid)
        let values = try await achievements.cloudItems(archiveID: uid)
        if fixtureMode { return values.count }
        try await assertIdentity(uid: uid, token: token)
        let payload: CountPayload = try await remote(
            path: "api/v1/achievements/upload",
            method: "POST",
            token: token,
            body: AchievementUpload(items: values.map(CloudAchievement.init)),
            as: CountPayload.self
        )
        return try count(from: payload)
    }

    func retrieveAchievements(uid: String) async throws -> Int {
        let token = try cloudToken(uid: uid)
        if fixtureMode { return 0 }
        try await assertIdentity(uid: uid, token: token)
        let payload: AchievementsPayload = try await remote(
            path: "api/v1/achievements/retrieve",
            method: "POST",
            token: token,
            body: EmptyRequest(),
            as: AchievementsPayload.self
        )
        return try await achievements.importCloud(
            archiveID: uid,
            values: payload.items.map(\.input)
        )
    }

    func deleteWishes(uid: String) async throws -> Int {
        let token = try cloudToken(uid: uid)
        if fixtureMode { return 0 }
        try await assertIdentity(uid: uid, token: token)
        let payload: CountPayload = try await remote(
            path: "api/v1/gacha",
            method: "DELETE",
            token: token,
            body: Optional<EmptyRequest>.none,
            as: CountPayload.self
        )
        return try count(from: payload)
    }

    func revokeSession(uid: String) async throws {
        let token = try cloudToken(uid: uid)
        if !fixtureMode {
            try await assertIdentity(uid: uid, token: token)
            _ = try await remote(
                path: "api/v1/auth/revoke",
                method: "POST",
                token: token,
                body: EmptyRequest(),
                as: EmptyResponse.self
            )
        }
        let key = Self.keychainAccount(uid: uid)
        let previous = try keychain.read(account: key)
        do {
            try keychain.delete(account: key)
            try await database.write { db in
                try db.execute(sql: "DELETE FROM cloud_sessions WHERE uid=?", arguments: [uid])
            }
        } catch {
            if let previous { try? keychain.save(previous, account: key) }
            throw error
        }
    }

    private func save(_ result: CloudCredentialResponse) async throws {
        guard Self.validUID(result.uid), Self.validToken(result.token),
              result.tokenRef == "keychain:cloud:\(result.uid)",
              result.reverifiedAt.timeIntervalSince1970.isFinite else {
            throw LauncherCoreError(code: "cloud_credential_invalid", message: "云端鉴权凭据无效")
        }
        let key = Self.keychainAccount(uid: result.uid)
        let previous = try keychain.read(account: key)
        do {
            try keychain.save(result.token, account: key)
            try await database.write { db in
                let now = CoreDate.string(Date())
                try db.execute(sql: """
                    INSERT INTO cloud_sessions(uid,token_ref,reverified_at,updated_at) VALUES(?,?,?,?)
                    ON CONFLICT(uid) DO UPDATE SET token_ref=excluded.token_ref,
                    reverified_at=excluded.reverified_at,updated_at=excluded.updated_at
                    """, arguments: [
                        result.uid, result.tokenRef, CoreDate.string(result.reverifiedAt), now
                    ])
            }
        } catch {
            if let previous { try? keychain.save(previous, account: key) }
            else { try? keychain.delete(account: key) }
            throw error
        }
    }

    private func assertIdentity(uid: String, token: String) async throws {
        let value: IdentityResponse = try await remote(
            path: "api/v1/me",
            method: "GET",
            token: token,
            body: Optional<EmptyRequest>.none,
            as: IdentityResponse.self
        )
        guard value.uid == uid else {
            throw LauncherCoreError(
                code: "cloud_identity_mismatch",
                message: "云端会话与角色 UID 不匹配"
            )
        }
    }

    private func cloudToken(uid: String) throws -> String {
        guard Self.validUID(uid) else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        guard let token = try keychain.read(account: Self.keychainAccount(uid: uid)) else {
            throw LauncherCoreError(code: "credential_missing", message: "云同步凭据不可用，请重新登录")
        }
        guard Self.validToken(token) else {
            throw LauncherCoreError(code: "cloud_credential_invalid", message: "云端同步凭据无效")
        }
        return token
    }

    private func count(from payload: CountPayload) throws -> Int {
        let value = payload.uploaded ?? payload.inserted ?? payload.deleted ?? 0
        guard (0...250_000).contains(value) else {
            throw LauncherCoreError(code: "cloud_payload_invalid", message: "云同步服务返回了无效数量")
        }
        return value
    }

    private func remote<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        token: String?,
        body: Body?,
        as type: Response.Type
    ) async throws -> Response {
        guard let baseURL,
              baseURL.scheme?.lowercased() == "https",
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.port == nil || baseURL.port == 443,
              baseURL.query == nil,
              baseURL.fragment == nil,
              let host = baseURL.host?.lowercased() else {
            throw LauncherCoreError(code: "cloud_not_configured", message: "云同步服务尚未配置")
        }
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoded = try JSONEncoder.api.encode(body)
            guard encoded.count <= 64 * 1024 * 1024 else {
                throw LauncherCoreError(code: "cloud_payload_too_large", message: "云同步数据超过大小限制")
            }
            request.httpBody = encoded
        }
        do {
            let payload = try await transport.send(
                request,
                policy: HTTPSHostPolicy(exactHosts: [host], suffixes: []),
                maximumBytes: 64 * 1024 * 1024
            )
            if payload.data.isEmpty {
                guard payload.statusCode == 204 else {
                    throw LauncherCoreError(code: "cloud_payload_invalid", message: "云端响应格式无效")
                }
                return try JSONDecoder.api.decode(Response.self, from: Data("{}".utf8))
            }
            guard (try? JSONSerialization.jsonObject(with: payload.data)) != nil else {
                throw LauncherCoreError(code: "cloud_payload_invalid", message: "云端响应格式无效")
            }
            guard (200..<300).contains(payload.statusCode) else {
                let error = try? JSONDecoder.api.decode(LauncherCoreError.self, from: payload.data)
                let forwardedCode = error.map { Self.forwardedErrors.contains($0.code) ? $0.code : "cloud_error" }
                    ?? "cloud_error"
                let forwardedMessage = error.map { value in
                    value.message.isEmpty || value.message.count > 1_024 ? "云端服务请求失败" : value.message
                } ?? "云端服务请求失败"
                throw LauncherCoreError(
                    code: forwardedCode,
                    message: forwardedMessage
                )
            }
            return try JSONDecoder.api.decode(type, from: payload.data)
        } catch let error as LauncherCoreError where error.code == "network_response_too_large" {
            try? recordFailure(path: path, code: "cloud_payload_invalid")
            throw LauncherCoreError(code: "cloud_payload_invalid", message: "云端响应格式无效")
        } catch let error as LauncherCoreError {
            try? recordFailure(path: path, code: error.code)
            throw error
        } catch is DecodingError {
            try? recordFailure(path: path, code: "cloud_payload_invalid")
            throw LauncherCoreError(code: "cloud_payload_invalid", message: "云端响应格式无效")
        } catch {
            try? recordFailure(path: path, code: "cloud_error")
            throw LauncherCoreError(code: "cloud_error", message: "云同步服务暂不可用")
        }
    }

    private func recordFailure(path: String, code: String) throws {
        let url = dataDirectory.appending(path: "cloud-sync-diagnostic.json")
        let data = try JSONSerialization.data(withJSONObject: [
            "timestamp": CoreDate.string(Date()),
            "path": path,
            "code": code
        ], options: [.sortedKeys])
        try GameFilesystem.writePrivate(data, to: url)
    }

    private nonisolated static func keychainAccount(uid: String) -> String { "cloud:\(uid)" }
    private nonisolated static let forwardedErrors: Set<String> = [
        "cloud_identity_mismatch", "cloud_session_expired", "cloud_reverification_required",
        "gacha_url_invalid", "gacha_url_expired", "gacha_url_unverified", "gacha_item_invalid",
        "gacha_upstream_invalid", "gacha_upstream_unavailable", "identity_mismatch",
        "reverify_required", "unauthorized", "achievement_items_invalid", "stored_data_invalid"
    ]

    private nonisolated static func validUID(_ value: String) -> Bool {
        value.range(of: #"^\d{9,10}$"#, options: .regularExpression) != nil
    }

    private nonisolated static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 16 * 1024
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

private struct CloudCredentialResponse: Codable, Sendable {
    let uid: String
    let token: String
    let tokenRef: String
    let reverifiedAt: Date
}

actor CoreUpdateService {
    private let cloudBaseURL: URL?
    private let transport: any HTTPTransport
    private let fixtureMode: Bool

    init(cloudBaseURL: URL?, transport: any HTTPTransport, fixtureMode: Bool) {
        self.cloudBaseURL = cloudBaseURL
        self.transport = transport
        self.fixtureMode = fixtureMode
    }

    func manifest() async throws -> AppUpdateManifest {
        if fixtureMode {
            return AppUpdateManifest(
                version: "0.1.1",
                downloadUrl: URL(string: "https://example.invalid/MHGLauncher.zip")!,
                sha256: String(repeating: "0", count: 64),
                size: 1,
                changelog: "Fixture"
            )
        }
        guard let base = cloudBaseURL,
              base.scheme?.lowercased() == "https",
              base.user == nil, base.password == nil,
              base.port == nil || base.port == 443,
              base.query == nil, base.fragment == nil,
              let host = base.host?.lowercased(), !host.isEmpty else {
            throw LauncherCoreError(code: "cloud_not_configured", message: "云端服务尚未配置")
        }
        let payload: HTTPPayload
        do {
            payload = try await transport.send(
                URLRequest(url: base.appending(path: "api/v1/updates/latest"), timeoutInterval: 15),
                policy: HTTPSHostPolicy(exactHosts: [host], suffixes: []),
                maximumBytes: 1024 * 1024
            )
        } catch let error as LauncherCoreError where error.code == "network_response_too_large" {
            throw LauncherCoreError(code: "update_payload_invalid", message: "云端更新信息无效")
        } catch {
            throw LauncherCoreError(code: "update_check_failed", message: "暂时无法检查应用更新")
        }
        guard (try? JSONSerialization.jsonObject(with: payload.data)) != nil else {
            throw LauncherCoreError(code: "update_payload_invalid", message: "云端更新信息无效")
        }
        guard (200..<300).contains(payload.statusCode) else {
            struct ErrorPayload: Decodable { let message: String? }
            let message = (try? JSONDecoder.api.decode(ErrorPayload.self, from: payload.data))?.message
                .flatMap { $0.isEmpty || $0.count > 1_024 ? nil : $0 }
                ?? "暂时无法检查应用更新"
            throw LauncherCoreError(code: "update_check_failed", message: message)
        }
        guard
              let manifest = try? JSONDecoder.api.decode(AppUpdateManifest.self, from: payload.data),
              manifest.version.utf8.count <= 128,
              manifest.version.range(
                of: #"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#,
                options: .regularExpression
              ) != nil,
              manifest.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              manifest.size > 0,
              manifest.size <= 4 * 1024 * 1024 * 1024,
              manifest.downloadUrl.scheme?.lowercased() == "https",
              manifest.downloadUrl.user == nil,
              manifest.downloadUrl.password == nil,
              manifest.downloadUrl.port == nil || manifest.downloadUrl.port == 443,
              manifest.downloadUrl.fragment == nil,
              manifest.downloadUrl.host?.isEmpty == false,
              manifest.downloadUrl.absoluteString.utf8.count <= 2_048,
              !manifest.changelog.isEmpty,
              manifest.changelog.count <= 20_000 else {
            throw LauncherCoreError(code: "update_payload_invalid", message: "云端更新信息无效")
        }
        return manifest
    }
}
