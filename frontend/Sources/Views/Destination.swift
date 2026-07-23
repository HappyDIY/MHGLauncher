import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case home = "主页"
    case game = "游戏"
    case wishes = "祈愿记录"
    case gachaHistory = "历史卡池"
    case cloudSync = "云同步"
    case notes = "实时便笺"
    case characters = "我的角色"
    case achievements = "成就管理"
    case notifications = "消息提醒"
    case account = "账号"

    var id: String { rawValue }

    init?(notificationValue: String) {
        switch notificationValue {
        case "notes": self = .notes
        case "gachaHistory": self = .gachaHistory
        case "game": self = .game
        default: return nil
        }
    }
    var icon: String {
        switch self {
        case .home: "house"
        case .game: "gamecontroller"
        case .wishes: "sparkles"
        case .gachaHistory: "calendar"
        case .cloudSync: "icloud"
        case .notes: "note.text"
        case .characters: "person.3"
        case .achievements: "trophy"
        case .notifications: "bell"
        case .account: "person.crop.circle"
        }
    }

    var accent: Color {
        switch self {
        case .home, .gachaHistory: .blue
        case .game: .indigo
        case .wishes, .cloudSync: .cyan
        case .notes, .notifications: .green
        case .characters: .mint
        case .achievements: .pink
        case .account: .orange
        }
    }
}
