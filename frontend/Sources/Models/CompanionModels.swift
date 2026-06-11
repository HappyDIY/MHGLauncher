import Foundation

struct WishRecord: Codable, Sendable, Identifiable {
    let id: String
    let uid: String
    let gachaType: String
    let itemId: String
    let name: String
    let itemType: String
    let rank: Int
    let time: Date
}

struct WishStatistics: Codable, Sendable, Identifiable {
    var id: String { gachaType }
    let uid: String
    let gachaType: String
    let total: Int
    let fiveStarCount: Int
    let pullsSinceFiveStar: Int
}

struct DailyNote: Codable, Sendable {
    let uid: String
    let currentResin: Int
    let maxResin: Int
    let finishedTasks: Int
    let totalTasks: Int
    let expeditionsFinished: Int
    let expeditionsTotal: Int
    let currentHomeCoin: Int
    let maxHomeCoin: Int
    let weeklyBossRemaining: Int
    let transformerReady: Bool
    let refreshedAt: Date
}

struct CredentialRequest: Codable {
    let credential: String
}

struct CountResponse: Codable {
    let inserted: Int?
    let imported: Int?
}

