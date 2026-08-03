import Foundation
import GRDB

actor CoreCharacterService {
    private let database: CoreDatabase
    private let records: any GameRecordProvider
    private let accounts: CoreAccountService

    init(
        database: CoreDatabase,
        records: any GameRecordProvider,
        accounts: CoreAccountService
    ) {
        self.database = database
        self.records = records
        self.accounts = accounts
    }

    func list(uid: String) async throws -> [GameCharacter] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM characters WHERE uid=? ORDER BY rarity DESC,level DESC,name",
                arguments: [uid]
            ).map(Self.character)
        }
    }

    func refresh() async throws -> [GameCharacter] {
        guard let role = try await accounts.selectedRole() else {
            throw LauncherCoreError(code: "role_missing", message: "尚未选择游戏角色")
        }
        let values = try await records.characters(
            credential: accounts.credential(),
            role: role
        )
        try await save(values)
        return values
    }

    func refreshDetail(avatarID: String) async throws -> GameCharacter {
        guard let role = try await accounts.selectedRole() else {
            throw LauncherCoreError(code: "role_missing", message: "尚未选择游戏角色")
        }
        let value = try await records.characterDetail(
            credential: accounts.credential(),
            role: role,
            avatarID: avatarID
        )
        try await save([value])
        return value
    }

    private func save(_ values: [GameCharacter]) async throws {
        try await database.write { db in
            for value in values {
                let payload = try value.payload.map { try JSONEncoder.api.encode($0) }
                try db.execute(sql: """
                    INSERT INTO characters(uid,avatar_id,name,element,level,rarity,constellation,fetter,
                    weapon_name,weapon_level,icon_url,payload,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(uid,avatar_id) DO UPDATE SET name=excluded.name,element=excluded.element,
                    level=excluded.level,rarity=excluded.rarity,constellation=excluded.constellation,
                    fetter=excluded.fetter,weapon_name=excluded.weapon_name,weapon_level=excluded.weapon_level,
                    icon_url=excluded.icon_url,payload=excluded.payload,updated_at=excluded.updated_at
                    """, arguments: [
                        value.uid, value.avatarId, value.name, value.element, value.level, value.rarity,
                        value.constellation, value.fetter, value.weaponName, value.weaponLevel,
                        value.iconUrl?.absoluteString,
                        payload.map { String(decoding: $0, as: UTF8.self) } ?? "{}",
                        CoreDate.string(value.updatedAt)
                    ])
            }
        }
    }

    private nonisolated static func character(_ row: Row) throws -> GameCharacter {
        let payloadText: String = row["payload"]
        let payload = payloadText == "{}" ? nil : try JSONDecoder.api.decode(
            CharacterPayload.self,
            from: Data(payloadText.utf8)
        )
        let iconText: String? = row["icon_url"]
        return GameCharacter(
            uid: row["uid"],
            avatarId: row["avatar_id"],
            name: row["name"],
            element: row["element"],
            level: row["level"],
            rarity: row["rarity"],
            constellation: row["constellation"],
            fetter: row["fetter"],
            weaponName: row["weapon_name"],
            weaponLevel: row["weapon_level"],
            iconUrl: iconText.flatMap(URL.init(string:)),
            payload: payload,
            updatedAt: CoreDate.parse(row["updated_at"])
        )
    }
}
