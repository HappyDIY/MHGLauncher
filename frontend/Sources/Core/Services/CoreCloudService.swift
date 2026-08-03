import Foundation
import GRDB

actor CoreCloudService {
    private struct GachaAuthRequest: Encodable { let gachaUrl: String }
    private struct EmptyRequest: Encodable {}
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
            uigfGachaType = value.gachaType == "400" ? "301" : value.gachaType
            itemId = value.itemId; name = value.name; itemType = value.itemType
            rank = value.rank; time = value.time
        }

        var record: WishRecord {
            WishRecord(
                id: id, uid: uid, gachaType: gachaType, itemId: itemId,
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
        try await database.read { db in
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
            }
        }
    }

    func login() async throws -> CloudLoginResult {
        guard let role = try await accounts.selectedRole() else {
            throw LauncherCoreError(code: "role_missing", message: "尚未选择游戏角色")
        }
        let credential: CloudCredentialResponse
        if fixtureMode {
            credential = CloudCredentialResponse(
                uid: role.uid,
                token: "fixture-cloud-token",
                tokenRef: "keychain:cloud:\(role.uid)",
                reverifiedAt: Date()
            )
        } else {
            let url = try await provider.gachaURL(
                credential: accounts.credential(),
                role: role
            )
            credential = try await remote(
                path: "api/v1/auth/gacha-url",
                method: "POST",
                token: nil,
                body: GachaAuthRequest(gachaUrl: url.absoluteString),
                as: CloudCredentialResponse.self
            )
            guard credential.uid == role.uid else {
                throw LauncherCoreError(
                    code: "cloud_identity_mismatch",
                    message: "云端鉴权 UID 与当前角色不匹配"
                )
            }
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
        return payload.uploaded ?? payload.inserted ?? 0
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
        return try await wishes.importCloud(payload.items.map(\.record))
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
        return payload.uploaded ?? payload.inserted ?? 0
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

    private func save(_ result: CloudCredentialResponse) async throws {
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
        guard let token = try keychain.read(account: Self.keychainAccount(uid: uid)) else {
            throw LauncherCoreError(code: "credential_missing", message: "云同步凭据不可用，请重新登录")
        }
        return token
    }

    private func remote<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        token: String?,
        body: Body?,
        as type: Response.Type
    ) async throws -> Response {
        guard let baseURL,
              baseURL.scheme == "https",
              baseURL.user == nil,
              baseURL.password == nil,
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
            request.httpBody = try JSONEncoder.api.encode(body)
        }
        do {
            let payload = try await transport.send(
                request,
                policy: HTTPSHostPolicy(exactHosts: [host], suffixes: []),
                maximumBytes: 64 * 1024 * 1024
            )
            guard (200..<300).contains(payload.statusCode) else {
                let error = try? JSONDecoder.api.decode(LauncherCoreError.self, from: payload.data)
                throw LauncherCoreError(
                    code: Self.forwardedErrors.contains(error?.code ?? "") ? error!.code : "cloud_error",
                    message: (error?.message.isEmpty == false && error!.message.count <= 1024)
                        ? error!.message : "云端服务请求失败"
                )
            }
            return try JSONDecoder.api.decode(type, from: payload.data)
        } catch let error as LauncherCoreError {
            try? recordFailure(path: path, code: error.code)
            throw error
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
        try data.write(to: url, options: [.atomic])
        try PrivateFilesystem.setPrivateFilePermissions(url)
    }

    private nonisolated static func keychainAccount(uid: String) -> String { "cloud:\(uid)" }
    private nonisolated static let forwardedErrors: Set<String> = [
        "cloud_identity_mismatch", "cloud_session_expired", "cloud_reverification_required"
    ]
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
              base.scheme == "https",
              let host = base.host?.lowercased() else {
            throw LauncherCoreError(code: "cloud_not_configured", message: "云端服务尚未配置")
        }
        let payload = try await transport.send(
            URLRequest(url: base.appending(path: "api/v1/updates/latest"), timeoutInterval: 15),
            policy: HTTPSHostPolicy(exactHosts: [host], suffixes: []),
            maximumBytes: 1024 * 1024
        )
        guard (200..<300).contains(payload.statusCode),
              let manifest = try? JSONDecoder.api.decode(AppUpdateManifest.self, from: payload.data),
              manifest.version.range(
                of: #"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#,
                options: .regularExpression
              ) != nil,
              manifest.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              manifest.size > 0,
              manifest.size <= 4 * 1024 * 1024 * 1024,
              manifest.downloadUrl.scheme == "https",
              manifest.downloadUrl.user == nil,
              manifest.downloadUrl.password == nil,
              !manifest.changelog.isEmpty,
              manifest.changelog.count <= 20_000 else {
            throw LauncherCoreError(code: "update_payload_invalid", message: "云端更新信息无效")
        }
        return manifest
    }
}
