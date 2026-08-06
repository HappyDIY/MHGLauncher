import Foundation
import GRDB

actor CoreNoteService {
    private let database: CoreDatabase
    private let provider: any GameProvider
    private let accounts: CoreAccountService

    init(database: CoreDatabase, provider: any GameProvider, accounts: CoreAccountService) {
        self.database = database
        self.provider = provider
        self.accounts = accounts
    }

    func refresh(challenge: String = "", challengePath: String = "") async throws -> DailyNote {
        guard challenge.utf8.count <= 4_096,
              !challenge.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              challengePath.utf8.count <= 128,
              ["", "/game_record/app/genshin/api/index", "/game_record/app/genshin/api/dailyNote"].contains(challengePath) else {
            throw LauncherCoreError(code: "note_challenge_invalid", message: "实时便笺验证信息无效")
        }
        guard let role = try await accounts.selectedRole() else {
            throw LauncherCoreError(code: "role_missing", message: "尚未选择游戏角色")
        }
        let credential = try await accounts.credential()
        let note = try await provider.dailyNote(
            credential: credential,
            role: role,
            challenge: challenge,
            challengePath: challengePath
        )
        guard note.uid == role.uid else {
            throw LauncherCoreError(code: "note_uid_mismatch", message: "实时便笺与当前 UID 不匹配")
        }
        let payload = try JSONEncoder.api.encode(note)
        guard payload.count <= 1024 * 1024 else {
            throw LauncherCoreError(code: "note_payload_too_large", message: "实时便笺数据超出限制")
        }
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO notes(uid,payload,refreshed_at) VALUES(?,?,?)
                ON CONFLICT(uid) DO UPDATE SET payload=excluded.payload,refreshed_at=excluded.refreshed_at
                """, arguments: [role.uid, String(decoding: payload, as: UTF8.self), CoreDate.string(note.refreshedAt)])
        }
        return note
    }

    func verify(challenge: String, validate: String, challengePath: String) async throws -> String {
        guard challenge.utf8.count <= 4_096,
              validate.utf8.count <= 4_096,
              !challenge.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !validate.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              challengePath.utf8.count <= 128,
              ["", "/game_record/app/genshin/api/index", "/game_record/app/genshin/api/dailyNote"].contains(challengePath) else {
            throw LauncherCoreError(code: "note_challenge_invalid", message: "实时便笺验证信息无效")
        }
        let result = try await provider.verifyNoteChallenge(
            credential: try await accounts.credential(),
            challenge: challenge,
            validate: validate,
            challengePath: challengePath
        )
        guard result.utf8.count <= 4_096,
              !result.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw LauncherCoreError(code: "note_challenge_invalid", message: "实时便笺验证结果无效")
        }
        return result
    }

    func get(uid: String) async throws -> DailyNote? {
        guard uid.range(of: #"^\d{9,10}$"#, options: .regularExpression) != nil else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        try await database.read { db in
            guard let payload = try String.fetchOne(
                db, sql: "SELECT payload FROM notes WHERE uid=?", arguments: [uid]
            ) else { return nil }
            guard payload.utf8.count <= 1024 * 1024,
                  let data = payload.data(using: .utf8) else {
                throw LauncherCoreError(code: "note_payload_too_large", message: "实时便笺数据超出限制")
            }
            let value = try JSONDecoder.api.decode(DailyNote.self, from: data)
            guard value.uid == uid else {
                throw LauncherCoreError(code: "note_uid_mismatch", message: "实时便笺与当前 UID 不匹配")
            }
            return value
        }
    }
}
