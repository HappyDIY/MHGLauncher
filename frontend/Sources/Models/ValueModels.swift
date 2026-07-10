import Foundation

struct GameCharacter: Codable, Sendable, Identifiable {
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
    let updatedAt: Date
}

enum CycleKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case abyss
    case theatre
    case hard

    var id: Self { self }
    var title: String {
        switch self {
        case .abyss: "深渊"
        case .theatre: "剧诗"
        case .hard: "危战"
        }
    }
}

struct CycleRecord: Codable, Sendable, Identifiable {
    var id: String { "\(kind.rawValue)-\(scheduleId)" }
    let uid: String
    let kind: CycleKind
    let scheduleId: String
    let title: String
    let summary: String
    let startedAt: Date?
    let endedAt: Date?
    let uploadedAt: Date?
    let updatedAt: Date
}

struct GachaEvent: Codable, Sendable, Identifiable {
    let id: String
    let version: String
    let gachaType: String
    let name: String
    let startedAt: Date
    let endedAt: Date
    let orangeUp: [String]
    let purpleUp: [String]
    let bannerUrl: URL?
    let updatedAt: Date
}

struct AchievementArchive: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let selected: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct AchievementItem: Codable, Sendable, Identifiable {
    var id: Int { achievementId }
    let archiveId: String
    let achievementId: Int
    let current: Int
    let status: Int
    let timestamp: Int
    let updatedAt: Date
}

struct AchievementGoal: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let order: Int
    let name: String
    let rewardCount: Int
    let iconUrl: URL?
}

struct AchievementEntry: Codable, Sendable, Identifiable, Equatable {
    var id: Int { achievementId }
    let archiveId: String
    let achievementId: Int
    let current: Int
    let status: Int
    let timestamp: Int
    let updatedAt: String
    let goal: Int
    let order: Int
    let title: String
    let description: String
    let progress: Int
    let version: String
    let rewardCount: Int
    let iconUrl: URL?
    let isDailyQuest: Bool
}

struct NotificationSettings: Codable, Sendable {
    var dailyCommissionEnabled: Bool
    var dailyCommissionTime: String
    var resinFullEnabled: Bool
    var abyssRefreshEnabled: Bool
    var theatreRefreshEnabled: Bool
    var hardRefreshEnabled: Bool
    var gachaRefreshEnabled: Bool
    var versionUpdateEnabled: Bool
}

struct NotificationEvent: Codable, Sendable, Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let body: String
    let destination: String
    let createdAt: Date
}

struct CloudLoginResult: Codable, Sendable {
    let uid: String
    let token: String
    let tokenRef: String
    let reverifiedAt: Date
}

struct CloudSession: Codable, Sendable {
    let uid: String
    let tokenRef: String
    let reverifiedAt: Date
    let updatedAt: Date
}

struct GachaURLRequest: Codable {
    let gachaUrl: String
    let token: String?
}

struct CloudUIDRequest: Codable {
    let uid: String
    let token: String
}

struct CloudCycleUploadRequest: Codable {
    let uid: String
    let token: String
    let scheduleId: String
}

struct AchievementArchiveRequest: Codable {
    let name: String
}

struct AchievementSaveRequest: Codable {
    let archiveId: String
    let items: [AchievementItemInput]
}

struct AchievementItemInput: Codable {
    let achievementId: Int
    let current: Int
    let status: Int
    let timestamp: Int
}
