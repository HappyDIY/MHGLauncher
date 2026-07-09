import Foundation

struct GameCharacter: Codable, Sendable, Identifiable, Equatable {
    var id: String { avatarId }
    let uid: String
    let avatarId: String
    let name: String
    let element: String
    let level: Int
    let rarity: Int
    let constellation: Int
    let fetter: Int
    let weaponName: String
    let weaponLevel: Int
    let iconUrl: URL?
    let payload: CharacterPayload?
    let updatedAt: Date

    var detailReady: Bool {
        payload?.weapon != nil || !(payload?.skills ?? []).isEmpty
    }

    var elementTitle: String {
        switch element.lowercased() {
        case "fire", "pyro": "火"
        case "water", "hydro": "水"
        case "wind", "anemo": "风"
        case "electric", "electro": "雷"
        case "grass", "dendro": "草"
        case "ice", "cryo": "冰"
        case "rock", "geo": "岩"
        default: element.isEmpty ? "未知" : element
        }
    }
}

struct CharacterPayload: Codable, Sendable, Equatable {
    let base: CharacterBase?
    let weapon: CharacterWeapon?
    let relics: [CharacterReliquary]?
    let constellations: [CharacterConstellation]?
    let selectedProperties: [CharacterProperty]?
    let skills: [CharacterSkill]?
    let recommendRelicProperty: CharacterRecommendation?
}

struct CharacterBase: Codable, Sendable, Equatable {
    let id: Int?
    let name: String?
    let icon: URL?
    let rarity: Int?
    let level: Int?
    let element: String?
    let fetter: Int?
}

struct CharacterWeapon: Codable, Sendable, Equatable {
    let id: Int?
    let name: String?
    let icon: URL?
    let rarity: Int?
    let level: Int?
    let affixLevel: Int?
    let mainProperty: CharacterProperty?
    let subProperty: CharacterProperty?
}

struct CharacterProperty: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(name ?? "")-\(value ?? "")-\(addValue ?? "")" }
    let name: String?
    let value: String?
    let addValue: String?
}

struct CharacterSkill: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(name ?? "")-\(level ?? 0)" }
    let name: String?
    let icon: URL?
    let level: Int?
    let maxLevel: Int?
    let desc: String?
}

struct CharacterConstellation: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(name ?? "")-\(isActivated ?? false)" }
    let name: String?
    let icon: URL?
    let isActivated: Bool?
    let description: String?
}

struct CharacterRecommendation: Codable, Sendable, Equatable {
    let sandProperties: [String]?
    let gobletProperties: [String]?
    let circletProperties: [String]?
    let subProperties: [String]?
}

struct CharacterReliquary: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(name ?? "")-\(pos ?? 0)" }
    let name: String?
    let icon: URL?
    let setName: String?
    let rarity: Int?
    let level: Int?
    let pos: Int?
    let mainProperty: CharacterProperty?
    let subProperties: [CharacterProperty]?
}
