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
    let iconUrl: URL?
}

struct WishStatistics: Codable, Sendable, Identifiable {
    var id: String { gachaType }
    let uid: String
    let gachaType: String
    let total: Int
    let fiveStarCount: Int
    let pullsSinceFiveStar: Int
}

struct WishBannerItem: Codable, Sendable, Identifiable {
    var id: String { "\(itemId)-\(pullNumber)" }
    let name: String
    let itemId: String
    let itemType: String
    let rank: Int
    let iconUrl: URL?
    let pullNumber: Int
    let pity: Int
    let time: Date
}

struct WishBannerDetail: Codable, Sendable, Identifiable {
    var id: String { gachaType }
    let uid: String
    let gachaType: String
    let total: Int
    let timeFrom: Date?
    let timeTo: Date?
    let fiveStarCount: Int
    let fourStarCount: Int
    let threeStarCount: Int
    let fiveStarPercent: Double
    let fourStarPercent: Double
    let threeStarPercent: Double
    let maxPity: Int
    let minPity: Int
    let averagePity: Double
    let lastPity: Int
    let lastPurplePity: Int
    let guaranteeThreshold: Int
    let fiveStarItems: [WishBannerItem]
    let fourStarItems: [WishBannerItem]
    // 限定池专属：每个限定五星所需的原石数量依据平均 UP 出金抽数推算；常驻/新手池为 0。
    // 可选以兼容未提供该字段的旧版后端。
    let averageUpPity: Double?
    // 限定池专属：小保底不歪率（排除大保底后的 50/50 胜率）；常驻/新手池为 0。
    // 可选以兼容未提供该字段的旧版后端。
    let smallGuaranteeWinRate: Double?
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

struct NoteRefreshRequest: Codable {
    let credential: String
    let xrpcChallenge: String
}

struct NoteVerificationRequest: Codable {
    let credential: String
    let challenge: String
    let validate: String
}

struct NoteVerificationResponse: Codable {
    let xrpcChallenge: String
}

struct GeetestChallenge: Identifiable {
    var id: String { challenge }
    let gt: String
    let challenge: String
}

struct CountResponse: Codable {
    let inserted: Int?
    let imported: Int?
    let deleted: Int?
    let uploaded: Int?
}
