import Foundation
import GRDB

actor CoreAccountService {
    private struct PendingLogin: Sendable {
        let identity: ProviderIdentity
        let roles: [GameRole]
        let expiresAt: Date
        let source: String
        let generation: Int
    }

    private let database: CoreDatabase
    private let provider: any GameProvider
    private let keychain: any KeychainStoring
    private var pending: [String: PendingLogin] = [:]
    private var generation = 0
    private var reservations: [String: Int] = [:]
    private var consumedSources = Set<String>()
    private static let maximumPendingLogins = 64

    init(database: CoreDatabase, provider: any GameProvider, keychain: any KeychainStoring) {
        self.database = database
        self.provider = provider
        self.keychain = keychain
    }

    func list() async throws -> [Account] {
        try await database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM account ORDER BY selected DESC,updated_at DESC"
            )
            guard rows.count <= 256 else {
                throw LauncherCoreError(code: "account_payload_too_large", message: "账号数量超出限制")
            }
            let values = rows.map(Self.account)
            guard values.allSatisfy(Self.validAccount) else {
                throw LauncherCoreError(code: "account_payload_invalid", message: "账号数据格式无效")
            }
            return values
        }
    }

    func selected() async throws -> Account? {
        try await database.read { db in
            let value = try Row.fetchOne(
                db,
                sql: "SELECT * FROM account ORDER BY selected DESC,updated_at DESC LIMIT 1"
            ).map(Self.account)
            if let value, !Self.validAccount(value) {
                throw LauncherCoreError(code: "account_payload_invalid", message: "账号数据格式无效")
            }
            return value
        }
    }

    func roles() async throws -> [GameRole] {
        guard let account = try await selected() else { return [] }
        return try await roles(aid: account.aid)
    }

    func syncRoles(aid: String, credential: String) async throws -> [GameRole] {
        guard Self.validAccountID(aid) else {
            throw LauncherCoreError(code: "account_invalid", message: "账号标识无效")
        }
        let target = try await list().first { $0.aid == aid }
        guard let target else {
            throw LauncherCoreError(code: "account_missing", message: "账号不存在")
        }
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validText(trimmed, maximum: 16 * 1024, allowEmpty: false) else {
            throw LauncherCoreError(code: "credential_invalid", message: "Cookie 凭据无效")
        }
        let identity = try await provider.identifyCredential(trimmed)
        guard identity.aid == target.aid, identity.mid == target.mid else {
            throw LauncherCoreError(code: "credential_identity_mismatch", message: "凭据与账号身份不匹配")
        }
        let incoming = try await provider.roles(credential: identity.credential)
        guard incoming.count <= 256 else {
            throw LauncherCoreError(code: "role_payload_too_large", message: "游戏角色数量超出限制")
        }
        var identifiers = Set<String>()
        guard incoming.allSatisfy({
            Self.validRole($0) && identifiers.insert($0.uid).inserted
        }) else {
            throw LauncherCoreError(code: "role_payload_invalid", message: "游戏角色信息无效")
        }
        let values = incoming.enumerated().map { index, role in
            GameRole(
                uid: role.uid,
                nickname: role.nickname,
                region: role.region,
                level: role.level,
                selected: index == 0
            )
        }
        try await database.write { db in
            let selectedUID: String? = try String.fetchOne(
                db,
                sql: "SELECT uid FROM roles WHERE account_aid=? AND selected=1",
                arguments: [aid]
            )
            let selected = values.contains { $0.uid == selectedUID }
                ? selectedUID : values.first?.uid
            try db.execute(sql: "DELETE FROM roles WHERE account_aid=?", arguments: [aid])
            for role in values {
                try db.execute(
                    sql: "INSERT INTO roles(uid,account_aid,nickname,region,level,selected) VALUES(?,?,?,?,?,?)",
                    arguments: [role.uid, aid, role.nickname, role.region, role.level, role.uid == selected]
                )
            }
        }
        return try await roles(aid: aid)
    }

    func selectedRole() async throws -> GameRole? {
        try await roles().first
    }

    func createQRSession() async throws -> QRSession {
        let session = try await provider.createQRSession()
        begin(source: "qr:\(session.id)")
        return session
    }

    func queryQRSession(_ id: String) async throws -> QRResult {
        let (session, identity) = try await provider.queryQRSession(id)
        guard let identity else { return QRResult(session: session, preparedLogin: nil) }
        let prepared = try await prepare(identity, source: "qr:\(id)")
        return QRResult(session: session, preparedLogin: prepared)
    }

    func sendMobileCaptcha(_ mobile: String) async throws -> MobileCaptchaSession {
        let trimmed = mobile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^1\d{10}$"#, options: .regularExpression) != nil else {
            throw LauncherCoreError(code: "mobile_invalid", message: "手机号格式无效")
        }
        let session = try await provider.createMobileCaptcha(trimmed)
        begin(source: "mobile:\(trimmed)")
        return session
    }

    func verifyMobileCaptcha(
        _ request: MobileCaptchaVerificationRequest
    ) async throws -> MobileCaptchaSession {
        let mobile = try Self.validMobile(request.mobile)
        guard Self.validText(request.sessionId, maximum: 256),
              Self.validText(request.challenge, maximum: 4_096),
              Self.validText(request.validate, maximum: 4_096) else {
            throw LauncherCoreError(code: "captcha_invalid", message: "验证码验证信息无效")
        }
        return try await provider.verifyMobileCaptcha(MobileCaptchaVerificationRequest(
            mobile: mobile,
            sessionId: request.sessionId,
            challenge: request.challenge,
            validate: request.validate
        ))
    }

    func prepareMobileLogin(_ request: MobileLoginRequest) async throws -> PreparedLogin {
        let mobile = try Self.validMobile(request.mobile)
        guard Self.validText(request.captcha, maximum: 4_096, allowEmpty: false),
              request.actionType.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
              request.aigis.map({ Self.validText($0, maximum: 16 * 1024) }) ?? true else {
            throw LauncherCoreError(code: "captcha_invalid", message: "手机号登录信息无效")
        }
        return try await prepare(
            provider.loginByMobileCaptcha(MobileLoginRequest(
                mobile: mobile,
                captcha: request.captcha,
                actionType: request.actionType,
                aigis: request.aigis
            )),
            source: "mobile:\(mobile)"
        )
    }

    func prepareCookieLogin(_ credential: String) async throws -> PreparedLogin {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validText(trimmed, maximum: 16 * 1024, allowEmpty: false) else {
            throw LauncherCoreError(code: "credential_invalid", message: "Cookie 凭据无效")
        }
        let source = "cookie:\(UUID().uuidString)"
        begin(source: source)
        return try await prepare(provider.identifyCredential(trimmed), source: source)
    }

    func commit(_ transactionID: String) async throws -> LoginCompleteResponse {
        removeExpiredPending()
        guard let value = pending[transactionID], value.generation == generation else {
            throw LauncherCoreError(code: "login_transaction_invalid", message: "登录事务无效或已过期")
        }
        pending[transactionID] = nil
        consumedSources.insert(value.source)
        let key = Self.keychainAccount(aid: value.identity.aid)
        let previous = try keychain.read(account: key)
        do {
            try keychain.save(value.identity.credential, account: key)
            let response = try await save(identity: value.identity, roles: value.roles)
            pending[transactionID] = nil
            return response
        } catch {
            if let previous { try? keychain.save(previous, account: key) }
            else { try? keychain.delete(account: key) }
            throw error
        }
    }

    func abort(_ transactionID: String) {
        pending[transactionID] = nil
    }

    func selectAccount(_ aid: String) async throws -> AccountSelectionResponse {
        guard Self.validAccountID(aid) else {
            throw LauncherCoreError(code: "account_invalid", message: "账号标识无效")
        }
        let account = try await database.write { db -> Account in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM account WHERE aid=?", arguments: [aid]) else {
                throw LauncherCoreError(code: "account_missing", message: "账号不存在")
            }
            let value = Self.account(row)
            guard Self.validAccount(value) else {
                throw LauncherCoreError(code: "account_payload_invalid", message: "账号数据格式无效")
            }
            try db.execute(sql: "UPDATE account SET selected=0")
            try db.execute(sql: "UPDATE account SET selected=1 WHERE aid=?", arguments: [aid])
            let selected = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM roles WHERE account_aid=? AND selected=1)",
                arguments: [aid]
            ) ?? false
            if !selected {
                try db.execute(sql: """
                    UPDATE roles SET selected=1 WHERE account_aid=?
                    AND uid=(SELECT uid FROM roles WHERE account_aid=? ORDER BY uid LIMIT 1)
                    """, arguments: [aid, aid])
            }
            return Account(
                aid: value.aid, mid: value.mid, nickname: value.nickname,
                credentialRef: value.credentialRef, selected: true, updatedAt: value.updatedAt
            )
        }
        return AccountSelectionResponse(account: account, roles: try await roles(aid: aid))
    }

    func selectRole(_ uid: String) async throws -> GameRole {
        guard Self.validUID(uid) else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        guard let account = try await selected() else {
            throw LauncherCoreError(code: "account_missing", message: "尚未登录账号")
        }
        return try await database.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM roles WHERE account_aid=? AND uid=?",
                arguments: [account.aid, uid]
            ) else {
                throw LauncherCoreError(code: "role_missing", message: "角色不存在")
            }
            let value = Self.role(row)
            guard Self.validRole(value) else {
                throw LauncherCoreError(code: "role_payload_invalid", message: "游戏角色信息无效")
            }
            try db.execute(sql: "UPDATE roles SET selected=0 WHERE account_aid=?", arguments: [account.aid])
            try db.execute(
                sql: "UPDATE roles SET selected=1 WHERE account_aid=? AND uid=?",
                arguments: [account.aid, uid]
            )
            return GameRole(
                uid: value.uid, nickname: value.nickname, region: value.region,
                level: value.level, selected: true
            )
        }
    }

    func logout() async throws {
        guard let account = try await selected() else { return }
        let key = Self.keychainAccount(aid: account.aid)
        let previous = try keychain.read(account: key)
        try keychain.delete(account: key)
        do {
            try await database.write { db in
                try db.execute(sql: "DELETE FROM account WHERE aid=?", arguments: [account.aid])
                if let next: String = try String.fetchOne(
                    db, sql: "SELECT aid FROM account ORDER BY updated_at DESC LIMIT 1"
                ) {
                    try db.execute(sql: "UPDATE account SET selected=(aid=?)", arguments: [next])
                }
            }
        } catch {
            if let previous { try? keychain.save(previous, account: key) }
            throw error
        }
    }

    func credential() async throws -> String {
        guard let account = try await selected(),
              Self.validAccountID(account.aid),
              account.credentialRef == "keychain:account:\(account.aid)",
              let value = try keychain.read(account: Self.keychainAccount(aid: account.aid)) else {
            throw LauncherCoreError(code: "credential_missing", message: "账号凭据不可用，请重新登录")
        }
        guard Self.validText(value, maximum: 16 * 1024, allowEmpty: false) else {
            throw LauncherCoreError(code: "credential_invalid", message: "账号凭据无效，请重新登录")
        }
        return value
    }

    private func prepare(_ identity: ProviderIdentity, source: String) async throws -> PreparedLogin {
        guard Self.validAccountID(identity.aid), identity.mid.utf8.count <= 256,
              identity.nickname.utf8.count <= 256,
              Self.validText(identity.mid, maximum: 256),
              Self.validText(identity.nickname, maximum: 256),
              Self.validText(identity.credential, maximum: 16 * 1024, allowEmpty: false) else {
            throw LauncherCoreError(code: "account_payload_invalid", message: "账号登录结果无效")
        }
        let incoming = try await provider.roles(credential: identity.credential)
        guard incoming.count <= 256 else {
            throw LauncherCoreError(code: "role_payload_too_large", message: "游戏角色数量超出限制")
        }
        var roleIDs = Set<String>()
        for role in incoming {
            guard Self.validUID(role.uid), Self.validText(role.nickname, maximum: 256),
                  role.region.range(of: #"^[A-Za-z0-9_-]{1,32}$"#, options: .regularExpression) != nil,
                  (0...100).contains(role.level), roleIDs.insert(role.uid).inserted else {
                throw LauncherCoreError(code: "role_payload_invalid", message: "游戏角色信息无效")
            }
        }
        removeExpiredPending()
        guard reservations[source] == generation else {
            throw LauncherCoreError(code: "login_intent_stale", message: "登录请求已被更新的操作取代")
        }
        if consumedSources.contains(source) {
            throw LauncherCoreError(code: "login_consumed", message: "登录事务已使用")
        }
        if let existing = pending.first(where: { $0.value.source == source && $0.value.generation == generation }) {
            return PreparedLogin(
                transactionId: existing.key,
                identity: AccountIdentity(
                    aid: existing.value.identity.aid,
                    mid: existing.value.identity.mid,
                    nickname: existing.value.identity.nickname
                ),
                roles: existing.value.roles, expiresAt: existing.value.expiresAt
            )
        }
        guard pending.count < Self.maximumPendingLogins else {
            throw LauncherCoreError(code: "login_pending_limit", message: "待完成的登录事务过多，请稍后重试")
        }
        let roles = incoming.enumerated().map {
            GameRole(
                uid: $0.element.uid,
                nickname: $0.element.nickname,
                region: $0.element.region,
                level: $0.element.level,
                selected: $0.offset == 0
            )
        }
        let id = UUID().uuidString
        let expiresAt = Date().addingTimeInterval(300)
        pending[id] = PendingLogin(
            identity: identity, roles: roles, expiresAt: expiresAt, source: source, generation: generation
        )
        return PreparedLogin(
            transactionId: id,
            identity: AccountIdentity(
                aid: identity.aid,
                mid: identity.mid,
                nickname: identity.nickname
            ),
            roles: roles,
            expiresAt: expiresAt
        )
    }

    private func save(
        identity: ProviderIdentity,
        roles incomingRoles: [GameRole]
    ) async throws -> LoginCompleteResponse {
        guard Self.validAccountID(identity.aid), incomingRoles.count <= 256,
              Self.validText(identity.mid, maximum: 256),
              Self.validText(identity.nickname, maximum: 256),
              incomingRoles.allSatisfy(Self.validRole) else {
            throw LauncherCoreError(code: "account_payload_invalid", message: "账号登录结果无效")
        }
        let updatedAt = Date()
        let credentialRef = "keychain:account:\(identity.aid)"
        try await database.write { db in
            let selectedUID = try String.fetchOne(
                db,
                sql: "SELECT uid FROM roles WHERE account_aid=? AND selected=1",
                arguments: [identity.aid]
            )
            let selected = incomingRoles.contains { $0.uid == selectedUID }
                ? selectedUID : incomingRoles.first?.uid
            try db.execute(sql: "UPDATE account SET selected=0")
            try db.execute(sql: """
                INSERT INTO account(aid,mid,nickname,credential_ref,selected,updated_at)
                VALUES(?,?,?,?,1,?) ON CONFLICT(aid) DO UPDATE SET mid=excluded.mid,
                nickname=excluded.nickname,credential_ref=excluded.credential_ref,
                selected=1,updated_at=excluded.updated_at
                """, arguments: [
                    identity.aid, identity.mid, identity.nickname, credentialRef,
                    CoreDate.string(updatedAt)
                ])
            try db.execute(sql: "DELETE FROM roles WHERE account_aid=?", arguments: [identity.aid])
            for role in incomingRoles {
                try db.execute(sql: """
                    INSERT INTO roles(uid,account_aid,nickname,region,level,selected) VALUES(?,?,?,?,?,?)
                    """, arguments: [
                        role.uid, identity.aid, role.nickname, role.region, role.level,
                        role.uid == selected
                    ])
            }
        }
        let account = Account(
            aid: identity.aid,
            mid: identity.mid,
            nickname: identity.nickname,
            credentialRef: credentialRef,
            selected: true,
            updatedAt: updatedAt
        )
        return LoginCompleteResponse(account: account, roles: try await roles(aid: identity.aid))
    }

    private func roles(aid: String) async throws -> [GameRole] {
        try await database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM roles WHERE account_aid=? ORDER BY selected DESC,uid",
                arguments: [aid]
            )
            guard rows.count <= 256 else {
                throw LauncherCoreError(code: "role_payload_too_large", message: "游戏角色数量超出限制")
            }
            let values = rows.map(Self.role)
            guard values.allSatisfy(Self.validRole) else {
                throw LauncherCoreError(code: "role_payload_invalid", message: "游戏角色信息无效")
            }
            return values
        }
    }

    private func removeExpiredPending() {
        let now = Date()
        pending = pending.filter { $0.value.expiresAt > now }
    }

    private func begin(source: String) {
        generation += 1
        pending.removeAll(keepingCapacity: true)
        consumedSources.remove(source)
        reservations[source] = generation
    }

    private nonisolated static func keychainAccount(aid: String) -> String { "account:\(aid)" }

    private nonisolated static func validAccountID(_ value: String) -> Bool {
        value.range(of: #"^\d{1,32}$"#, options: .regularExpression) != nil
    }

    private nonisolated static func validUID(_ value: String) -> Bool {
        value.range(of: #"^\d{9,10}$"#, options: .regularExpression) != nil
    }

    private nonisolated static func validMobile(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^1\d{10}$"#, options: .regularExpression) != nil else {
            throw LauncherCoreError(code: "mobile_invalid", message: "手机号格式无效")
        }
        return trimmed
    }

    private nonisolated static func validText(
        _ value: String,
        maximum: Int,
        allowEmpty: Bool = true
    ) -> Bool {
        (allowEmpty || !value.isEmpty) && value.utf8.count <= maximum
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private nonisolated static func validAccount(_ value: Account) -> Bool {
        validAccountID(value.aid)
            && validText(value.mid, maximum: 256)
            && validText(value.nickname, maximum: 256)
            && value.credentialRef == "keychain:account:\(value.aid)"
            && value.updatedAt.timeIntervalSince1970.isFinite
    }

    private nonisolated static func validRole(_ value: GameRole) -> Bool {
        validUID(value.uid)
            && validText(value.nickname, maximum: 256)
            && value.region.range(of: #"^[A-Za-z0-9_-]{1,32}$"#, options: .regularExpression) != nil
            && (0...100).contains(value.level)
    }

    private nonisolated static func account(_ row: Row) -> Account {
        Account(
            aid: row["aid"],
            mid: row["mid"],
            nickname: row["nickname"],
            credentialRef: row["credential_ref"],
            selected: row["selected"],
            updatedAt: CoreDate.parse(row["updated_at"])
        )
    }

    private nonisolated static func role(_ row: Row) -> GameRole {
        GameRole(
            uid: row["uid"],
            nickname: row["nickname"],
            region: row["region"],
            level: row["level"],
            selected: row["selected"]
        )
    }
}
