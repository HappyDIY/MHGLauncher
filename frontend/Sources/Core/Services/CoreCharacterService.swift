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
        guard Self.validUID(uid) else {
            throw LauncherCoreError(code: "uid_invalid", message: "角色 UID 无效")
        }
        return try await database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM characters WHERE uid=? ORDER BY rarity DESC,level DESC,name",
                arguments: [uid]
            )
            guard rows.count <= 256 else {
                throw LauncherCoreError(code: "character_payload_too_large", message: "角色数据数量超出限制")
            }
            return try rows.map(Self.character)
        }
    }

    func refresh() async throws -> [GameCharacter] {
        guard let role = try await accounts.selectedRole() else {
            throw LauncherCoreError(code: "role_missing", message: "尚未选择游戏角色")
        }
        let values = try await records.characters(
            credential: try await accounts.credential(),
            role: role
        )
        guard values.allSatisfy({ $0.uid == role.uid }) else {
            throw LauncherCoreError(code: "character_uid_mismatch", message: "角色数据与当前 UID 不匹配")
        }
        try await save(values)
        return values
    }

    func refreshDetail(avatarID: String) async throws -> GameCharacter {
        guard avatarID.range(of: #"^\d{1,16}$"#, options: .regularExpression) != nil else {
            throw LauncherCoreError(code: "character_id_invalid", message: "角色标识无效")
        }
        guard let role = try await accounts.selectedRole() else {
            throw LauncherCoreError(code: "role_missing", message: "尚未选择游戏角色")
        }
        let value = try await records.characterDetail(
            credential: try await accounts.credential(),
            role: role,
            avatarID: avatarID
        )
        guard value.uid == role.uid else {
            throw LauncherCoreError(code: "character_uid_mismatch", message: "角色数据与当前 UID 不匹配")
        }
        try await save([value])
        return value
    }

    private func save(_ values: [GameCharacter]) async throws {
        guard values.count <= 256 else {
            throw LauncherCoreError(code: "character_payload_too_large", message: "角色数据数量超出限制")
        }
        for value in values {
            guard Self.validUID(value.uid),
                  value.avatarId.range(of: #"^\d{1,16}$"#, options: .regularExpression) != nil,
                  value.name.utf8.count <= 256, value.element.utf8.count <= 64,
                  value.weaponName.utf8.count <= 256,
                  !value.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !value.element.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !value.weaponName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  (value.iconUrl.map {
                      $0.absoluteString.utf8.count <= 16 * 1024
                          && !$0.absoluteString.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                  } ?? true),
                  (0...100).contains(value.level), (0...5).contains(value.rarity),
                  (0...6).contains(value.constellation), (0...10).contains(value.fetter),
                  (0...100).contains(value.weaponLevel),
                  value.updatedAt.timeIntervalSince1970.isFinite else {
                throw LauncherCoreError(code: "character_payload_invalid", message: "角色数据格式无效")
            }
        }
        try await database.write { db in
            for value in values {
                let payload = try value.payload.map { try JSONEncoder.api.encode($0) }
                guard (payload?.count ?? 0) <= 4 * 1024 * 1024 else {
                    throw LauncherCoreError(code: "character_payload_too_large", message: "角色详情数据超出限制")
                }
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
        guard payloadText.utf8.count <= 4 * 1024 * 1024 else {
            throw LauncherCoreError(code: "character_payload_too_large", message: "角色详情数据超出限制")
        }
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

    private nonisolated static func validUID(_ value: String) -> Bool {
        value.range(of: #"^\d{9,10}$"#, options: .regularExpression) != nil
    }
}
