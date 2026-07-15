import Foundation

struct CharacterProperty: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(name ?? "")-\(value ?? "")-\(addValue ?? "")" }
    let name: String?
    let value: String?
    let addValue: String?

    var formattedAddValue: String? {
        guard let addValue, !addValue.isEmpty else { return nil }
        return addValue.hasPrefix("+") || addValue.hasPrefix("-")
            ? addValue
            : "+\(addValue)"
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case value
        case addValue
        case propertyType
        case base
        case add
        case final
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let type = try values.decodeIfPresent(Int.self, forKey: .propertyType)
        name = try values.decodeIfPresent(String.self, forKey: .name)
            ?? CharacterFightProperty.title(for: type)
        value = try values.decodeIfPresent(String.self, forKey: .value)
            ?? values.decodeIfPresent(String.self, forKey: .final)
            ?? values.decodeIfPresent(String.self, forKey: .base)
        let addition = try values.decodeIfPresent(String.self, forKey: .addValue)
            ?? values.decodeIfPresent(String.self, forKey: .add)
        addValue = addition?.isEmpty == false ? addition : nil
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(name, forKey: .name)
        try values.encodeIfPresent(value, forKey: .value)
        try values.encodeIfPresent(addValue, forKey: .addValue)
    }
}

enum CharacterFightProperty {
    static func title(for type: Int?) -> String? {
        guard let type else { return nil }
        return switch type {
        case 1: "基础生命值"
        case 2: "生命值"
        case 3: "生命值百分比"
        case 4: "基础攻击力"
        case 5: "攻击力"
        case 6: "攻击力百分比"
        case 7: "基础防御力"
        case 8: "防御力"
        case 9: "防御力百分比"
        case 20: "暴击率"
        case 21: "抗暴率"
        case 22: "暴击伤害"
        case 23: "元素充能效率"
        case 24: "伤害加成"
        case 26: "治疗加成"
        case 27: "受治疗加成"
        case 28: "元素精通"
        case 30: "物理伤害加成"
        case 40: "火元素伤害加成"
        case 41: "雷元素伤害加成"
        case 42: "水元素伤害加成"
        case 43: "草元素伤害加成"
        case 44: "风元素伤害加成"
        case 45: "岩元素伤害加成"
        case 46: "冰元素伤害加成"
        case 2000: "生命值上限"
        case 2001: "攻击力"
        case 2002: "防御力"
        default: "属性 \(type)"
        }
    }
}
