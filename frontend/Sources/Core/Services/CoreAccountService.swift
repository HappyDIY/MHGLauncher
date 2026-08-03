import Foundation
import GRDB

actor CoreAccountService {
    private struct PendingLogin: Sendable {
        let identity: ProviderIdentity
        let roles: [GameRole]
        let expiresAt: Date
    }

    private let database: CoreDatabase
    private let provider: any GameProvider
    private let keychain: any KeychainStoring
    private var pending: [String: PendingLogin] = [:]

    init(database: CoreDatabase, provider: any GameProvider, keychain: any KeychainStoring) {
        self.database = database
        self.provider = provider
        self.keychain = keychain
    }

    func list() async throws -> [Account] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM account ORDER BY selected DESC,updated_at DESC"
            ).map(Self.account)
        }
    }

    func selected() async throws -> Account? {
        try await database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM account ORDER BY selected DESC,updated_at DESC LIMIT 1"
            ).map(Self.account)
        }
    }

    func roles() async throws -> [GameRole] {
        guard let account = try await selected() else { return [] }
        return try await roles(aid: account.aid)
    }

    func selectedRole() async throws -> GameRole? {
        try await roles().first
    }

    func createQRSession() async throws -> QRSession {
        try await provider.createQRSession()
    }

    func queryQRSession(_ id: String) async throws -> QRResult {
        let (session, identity) = try await provider.queryQRSession(id)
        guard let identity else { return QRResult(session: session, preparedLogin: nil) }
        let prepared = try await prepare(identity)
        return QRResult(session: session, preparedLogin: prepared)
    }

    func sendMobileCaptcha(_ mobile: String) async throws -> MobileCaptchaSession {
        let trimmed = mobile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^1\d{10}$"#, options: .regularExpression) != nil else {
            throw LauncherCoreError(code: "mobile_invalid", message: "手机号格式无效")
        }
        return try await provider.createMobileCaptcha(trimmed)
    }

    func verifyMobileCaptcha(
        _ request: MobileCaptchaVerificationRequest
    ) async throws -> MobileCaptchaSession {
        try await provider.verifyMobileCaptcha(request)
    }

    func prepareMobileLogin(_ request: MobileLoginRequest) async throws -> PreparedLogin {
        try await prepare(provider.loginByMobileCaptcha(request))
    }

    func prepareCookieLogin(_ credential: String) async throws -> PreparedLogin {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 16 * 1024 else {
            throw LauncherCoreError(code: "credential_invalid", message: "Cookie 凭据无效")
        }
        return try await prepare(provider.identifyCredential(trimmed))
    }

    func commit(_ transactionID: String) async throws -> LoginCompleteResponse {
        removeExpiredPending()
        guard let value = pending[transactionID] else {
            throw LauncherCoreError(code: "login_transaction_missing", message: "登录事务不存在或已过期")
        }
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
        let account = try await database.write { db -> Account in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM account WHERE aid=?", arguments: [aid]) else {
                throw LauncherCoreError(code: "account_missing", message: "账号不存在")
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
            let value = Self.account(row)
            return Account(
                aid: value.aid, mid: value.mid, nickname: value.nickname,
                credentialRef: value.credentialRef, selected: true, updatedAt: value.updatedAt
            )
        }
        return AccountSelectionResponse(account: account, roles: try await roles(aid: aid))
    }

    func selectRole(_ uid: String) async throws -> GameRole {
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
            try db.execute(sql: "UPDATE roles SET selected=0 WHERE account_aid=?", arguments: [account.aid])
            try db.execute(
                sql: "UPDATE roles SET selected=1 WHERE account_aid=? AND uid=?",
                arguments: [account.aid, uid]
            )
            let value = Self.role(row)
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
              let value = try keychain.read(account: Self.keychainAccount(aid: account.aid)) else {
            throw LauncherCoreError(code: "credential_missing", message: "账号凭据不可用，请重新登录")
        }
        return value
    }

    private func prepare(_ identity: ProviderIdentity) async throws -> PreparedLogin {
        let roles = try await provider.roles(credential: identity.credential).enumerated().map {
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
        pending[id] = PendingLogin(identity: identity, roles: roles, expiresAt: expiresAt)
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
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM roles WHERE account_aid=? ORDER BY selected DESC,uid",
                arguments: [aid]
            ).map(Self.role)
        }
    }

    private func removeExpiredPending() {
        let now = Date()
        pending = pending.filter { $0.value.expiresAt > now }
    }

    private nonisolated static func keychainAccount(aid: String) -> String { "account:\(aid)" }

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
