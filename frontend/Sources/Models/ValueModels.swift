import Foundation

struct GachaEvent: Codable, Sendable, Identifiable {
    let id: String
    let version: String
    let gachaType: String
    let name: String
    let startedAt: Date?
    let endedAt: Date?
    let orangeUp: [String]
    let purpleUp: [String]
    var orangeUpIcons: [String: URL]? = nil
    var purpleUpIcons: [String: URL]? = nil
    let bannerUrl: URL?
    let updatedAt: Date
}

struct GachaResourceStatus: Codable, Sendable, Equatable {
    let state: String
    let version: String?
    let eventCount: Int
    let imageCount: Int
    let installedBytes: Int64
    let installedAt: Date?

    var isReady: Bool { state == "ready" }
}

struct GachaResourceInstallRequest: Codable {}

struct AchievementArchive: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let selected: Bool
    let createdAt: Date
    let updatedAt: Date
    var revision: Int? = nil
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

struct NotificationSettings: Codable, Sendable, Equatable {
    var dailyCommissionEnabled: Bool
    var dailyCommissionTime: String
    var resinFullEnabled: Bool
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

struct NotificationAcknowledgement: Codable, Sendable {
    let keys: [String]
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
}

struct CloudUIDRequest: Codable {
    let uid: String
    let token: String
}

struct AchievementSaveRequest: Codable {
    let archiveId: String
    let expectedRevision: Int
    let items: [AchievementItemInput]
}

struct AchievementSnapshot: Codable, Sendable {
    let archive: AchievementArchive
    let entries: [AchievementEntry]
    let revision: Int
}

struct AchievementItemInput: Codable {
    let achievementId: Int
    let current: Int
    let status: Int
    let timestamp: Int
}
