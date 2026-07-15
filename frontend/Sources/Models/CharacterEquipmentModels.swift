import Foundation

struct CharacterRecommendation: Codable, Sendable, Equatable {
    let sandProperties: [String]?
    let gobletProperties: [String]?
    let circletProperties: [String]?
    let subProperties: [String]?

    private enum CodingKeys: String, CodingKey {
        case sandProperties
        case gobletProperties
        case circletProperties
        case subProperties
        case recommendProperties
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try values.decodeIfPresent(RawRecommendation.self, forKey: .recommendProperties)
        sandProperties = try values.decodeIfPresent([String].self, forKey: .sandProperties)
            ?? Self.names(raw?.sandMainPropertyList)
        gobletProperties = try values.decodeIfPresent([String].self, forKey: .gobletProperties)
            ?? Self.names(raw?.gobletMainPropertyList)
        circletProperties = try values.decodeIfPresent([String].self, forKey: .circletProperties)
            ?? Self.names(raw?.circletMainPropertyList)
        subProperties = try values.decodeIfPresent([String].self, forKey: .subProperties)
            ?? Self.names(raw?.subPropertyList)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(sandProperties, forKey: .sandProperties)
        try values.encodeIfPresent(gobletProperties, forKey: .gobletProperties)
        try values.encodeIfPresent(circletProperties, forKey: .circletProperties)
        try values.encodeIfPresent(subProperties, forKey: .subProperties)
    }

    private static func names(_ types: [Int]?) -> [String]? {
        let result = (types ?? []).compactMap { CharacterFightProperty.title(for: $0) }
        return result.isEmpty ? nil : result
    }
}

private struct RawRecommendation: Decodable {
    let sandMainPropertyList: [Int]?
    let gobletMainPropertyList: [Int]?
    let circletMainPropertyList: [Int]?
    let subPropertyList: [Int]?
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

    private enum CodingKeys: String, CodingKey {
        case name, icon, setName, rarity, level, pos, mainProperty, subProperties
        case setInfo = "set"
        case subPropertyList
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        icon = try values.decodeIfPresent(URL.self, forKey: .icon)
        let set = try values.decodeIfPresent(RelicSet.self, forKey: .setInfo)
        setName = try values.decodeIfPresent(String.self, forKey: .setName) ?? set?.name
        rarity = try values.decodeIfPresent(Int.self, forKey: .rarity)
        level = try values.decodeIfPresent(Int.self, forKey: .level)
        pos = try values.decodeIfPresent(Int.self, forKey: .pos)
        mainProperty = try values.decodeIfPresent(CharacterProperty.self, forKey: .mainProperty)
        subProperties = try values.decodeIfPresent([CharacterProperty].self, forKey: .subProperties)
            ?? values.decodeIfPresent([CharacterProperty].self, forKey: .subPropertyList)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(name, forKey: .name)
        try values.encodeIfPresent(icon, forKey: .icon)
        try values.encodeIfPresent(setName, forKey: .setName)
        try values.encodeIfPresent(rarity, forKey: .rarity)
        try values.encodeIfPresent(level, forKey: .level)
        try values.encodeIfPresent(pos, forKey: .pos)
        try values.encodeIfPresent(mainProperty, forKey: .mainProperty)
        try values.encodeIfPresent(subProperties, forKey: .subProperties)
    }
}

private struct RelicSet: Decodable {
    let name: String?
}
