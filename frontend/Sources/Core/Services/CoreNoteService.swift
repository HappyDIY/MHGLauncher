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
        try await provider.verifyNoteChallenge(
            credential: accounts.credential(),
            challenge: challenge,
            validate: validate,
            challengePath: challengePath
        )
    }

    func get(uid: String) async throws -> DailyNote? {
        try await database.read { db in
            guard let payload = try String.fetchOne(
                db, sql: "SELECT payload FROM notes WHERE uid=?", arguments: [uid]
            ), let data = payload.data(using: .utf8) else { return nil }
            return try JSONDecoder.api.decode(DailyNote.self, from: data)
        }
    }
}
