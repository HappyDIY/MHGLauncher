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
    case abyss = "深渊"
    case theatre = "剧诗"
    case hard = "危战"
    case notifications = "消息提醒"
    case account = "账号"

    var id: String { rawValue }
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
        case .abyss: "moon.stars"
        case .theatre: "theatermasks"
        case .hard: "flame"
        case .notifications: "bell"
        case .account: "person.crop.circle"
        }
    }

    var accent: Color {
        switch self {
        case .home, .gachaHistory: .blue
        case .game, .abyss: .indigo
        case .wishes, .cloudSync: .cyan
        case .notes, .notifications: .green
        case .characters, .theatre: .mint
        case .achievements, .hard: .pink
        case .account: .orange
        }
    }
}
