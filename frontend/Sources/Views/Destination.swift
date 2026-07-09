import Foundation

enum Destination: String, CaseIterable, Identifiable {
    case home = "主页"
    case game = "游戏"
    case wishes = "祈愿记录"
    case characters = "我的角色"
    case notes = "实时便笺"
    case account = "账号"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .game: "gamecontroller"
        case .wishes: "sparkles"
        case .characters: "person.3"
        case .notes: "note.text"
        case .account: "person.crop.circle"
        }
    }
}
