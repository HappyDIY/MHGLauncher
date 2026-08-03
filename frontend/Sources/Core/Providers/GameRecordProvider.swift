import Foundation

protocol GameRecordProvider: Sendable {
    func characters(credential: String, role: GameRole) async throws -> [GameCharacter]
    func characterDetail(
        credential: String,
        role: GameRole,
        avatarID: String
    ) async throws -> GameCharacter
}

struct FixtureGameRecordProvider: GameRecordProvider {
    func characters(credential: String, role: GameRole) async throws -> [GameCharacter] {
        [
            character(
                uid: role.uid,
                avatarID: "10000089",
                name: "芙宁娜",
                element: "Water",
                constellation: 2,
                weapon: "静水流涌之辉"
            ),
            character(
                uid: role.uid,
                avatarID: "10000075",
                name: "流浪者",
                element: "Wind",
                constellation: 0,
                weapon: "图莱杜拉的回忆"
            )
        ]
    }

    func characterDetail(
        credential: String,
        role: GameRole,
        avatarID: String
    ) async throws -> GameCharacter {
        try await characters(credential: credential, role: role).first { $0.avatarId == avatarID }
            ?? character(
                uid: role.uid,
                avatarID: avatarID,
                name: "旅行者",
                element: "None",
                constellation: 0,
                weapon: "无锋剑"
            )
    }

    private func character(
        uid: String,
        avatarID: String,
        name: String,
        element: String,
        constellation: Int,
        weapon: String
    ) -> GameCharacter {
        GameCharacter(
            uid: uid,
            avatarId: avatarID,
            name: name,
            element: element,
            level: 90,
            rarity: 5,
            constellation: constellation,
            fetter: 10,
            weaponName: weapon,
            weaponLevel: 90,
            iconUrl: nil,
            payload: nil,
            updatedAt: Date()
        )
    }
}
