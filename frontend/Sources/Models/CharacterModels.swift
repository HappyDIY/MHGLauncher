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
        payload?.selectedProperties != nil
            && payload?.skills != nil
            && payload?.constellations != nil
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
    let additionalFields: [String: JSONValue]
    let rawFields: [String: JSONValue]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case base, weapon, relics, constellations, selectedProperties, skills
        case recommendRelicProperty
    }

    init(
        base: CharacterBase?,
        weapon: CharacterWeapon?,
        relics: [CharacterReliquary]?,
        constellations: [CharacterConstellation]?,
        selectedProperties: [CharacterProperty]?,
        skills: [CharacterSkill]?,
        recommendRelicProperty: CharacterRecommendation?,
        additionalFields: [String: JSONValue] = [:],
        rawFields: [String: JSONValue] = [:]
    ) {
        self.base = base
        self.weapon = weapon
        self.relics = relics
        self.constellations = constellations
        self.selectedProperties = selectedProperties
        self.skills = skills
        self.recommendRelicProperty = recommendRelicProperty
        self.additionalFields = additionalFields
        self.rawFields = rawFields
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        base = try? values.decodeIfPresent(CharacterBase.self, forKey: .base)
        weapon = try? values.decodeIfPresent(CharacterWeapon.self, forKey: .weapon)
        relics = try? values.decodeIfPresent([CharacterReliquary].self, forKey: .relics)
        constellations = try? values.decodeIfPresent([CharacterConstellation].self, forKey: .constellations)
        selectedProperties = try? values.decodeIfPresent([CharacterProperty].self, forKey: .selectedProperties)
        skills = try? values.decodeIfPresent([CharacterSkill].self, forKey: .skills)
        recommendRelicProperty = try? values.decodeIfPresent(
            CharacterRecommendation.self, forKey: .recommendRelicProperty
        )

        let dynamic = try decoder.container(keyedBy: CharacterDynamicCodingKey.self)
        let known = Self.knownKeys
        let decoded = Set([
            base == nil ? nil : "base",
            weapon == nil ? nil : "weapon",
            relics == nil ? nil : "relics",
            constellations == nil ? nil : "constellations",
            selectedProperties == nil ? nil : "selectedProperties",
            skills == nil ? nil : "skills",
            recommendRelicProperty == nil ? nil : "recommendRelicProperty"
        ].compactMap { $0 })
        rawFields = try dynamic.allKeys.reduce(into: [String: JSONValue]()) { result, key in
            result[key.stringValue] = try dynamic.decode(JSONValue.self, forKey: key)
        }
        additionalFields = rawFields.reduce(into: [String: JSONValue]()) { result, pair in
            let key = pair.key
            let canonical = Self.canonicalKnownKey(key)
            guard !known.contains(key) || !decoded.contains(canonical) else { return }
            result[key] = pair.value
        }
    }

    func encode(to encoder: Encoder) throws {
        var dynamic = encoder.container(keyedBy: CharacterDynamicCodingKey.self)
        var fields = rawFields
        for (key, value) in additionalFields where fields[key] == nil {
            fields[key] = value
        }
        try Self.overlay(base, canonicalKey: "base", in: &fields)
        try Self.overlay(weapon, canonicalKey: "weapon", in: &fields)
        try Self.overlay(relics, canonicalKey: "relics", in: &fields)
        try Self.overlay(constellations, canonicalKey: "constellations", in: &fields)
        try Self.overlay(selectedProperties, canonicalKey: "selectedProperties", in: &fields)
        try Self.overlay(skills, canonicalKey: "skills", in: &fields)
        try Self.overlay(recommendRelicProperty, canonicalKey: "recommendRelicProperty", in: &fields)
        for (key, value) in fields {
            guard let codingKey = CharacterDynamicCodingKey(stringValue: key) else { continue }
            try dynamic.encode(value, forKey: codingKey)
        }
    }

    private static func overlay<T: Encodable>(
        _ value: T?,
        canonicalKey: String,
        in fields: inout [String: JSONValue]
    ) throws {
        guard let value else { return }
        let data = try JSONEncoder.api.encode(value)
        let encoded = try JSONDecoder.api.decode(JSONValue.self, from: data)
        let keys = fields.keys.filter { canonicalKnownKey($0) == canonicalKey }
        if keys.isEmpty {
            fields[snakeKey(canonicalKey)] = encoded
        } else {
            for key in keys { fields[key] = merge(fields[key], encoded) }
        }
    }

    private static func merge(_ raw: JSONValue?, _ value: JSONValue) -> JSONValue {
        guard let raw else { return value }
        switch (raw, value) {
        case (.object(let old), .object(let current)):
            var merged = old
            for (key, child) in current { merged[key] = merge(old[key], child) }
            return .object(merged)
        case (.array(let old), .array(let current)):
            return .array(current.enumerated().map { index, child in
                merge(index < old.count ? old[index] : nil, child)
            })
        default:
            return value
        }
    }

    private static let knownKeys: Set<String> = [
            "base", "weapon", "relics", "constellations", "selectedProperties", "selected_properties",
            "skills", "recommendRelicProperty", "recommend_relic_property"
    ]

    private static func canonicalKnownKey(_ value: String) -> String {
        switch value {
        case "selected_properties": return "selectedProperties"
        case "recommend_relic_property": return "recommendRelicProperty"
        default: return value
        }
    }

    private static func snakeKey(_ value: String) -> String {
        switch value {
        case "selectedProperties": return "selected_properties"
        case "recommendRelicProperty": return "recommend_relic_property"
        default: return value
        }
    }
}

private struct CharacterDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) { return nil }
}

struct CharacterBase: Codable, Sendable, Equatable {
    let id: Int?
    let name: String?
    let icon: URL?
    let rarity: Int?
    let level: Int?
    let element: String?
    let fetter: Int?
    let weapon: CharacterWeapon?
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

struct CharacterSkill: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(skillId ?? 0)-\(name ?? "")-\(level ?? 0)" }
    let skillId: Int? = nil
    let name: String?
    let icon: URL?
    let skillType: Int?
    let level: Int?
    let maxLevel: Int?
    let desc: String?

    var isCombatTalent: Bool { skillType == 1 }
}

struct CharacterConstellation: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(assetId ?? 0)-\(name ?? "")-\(isActivated ?? false)" }
    let assetId: Int?
    let name: String?
    let icon: URL?
    let isActivated: Bool?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case assetId = "id"
        case name, icon, isActivated, description
    }

    init(
        assetId: Int? = nil,
        name: String?,
        icon: URL?,
        isActivated: Bool?,
        description: String?
    ) {
        self.assetId = assetId
        self.name = name
        self.icon = icon
        self.isActivated = isActivated
        self.description = description
    }
}
