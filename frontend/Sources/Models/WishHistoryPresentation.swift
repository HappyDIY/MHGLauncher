import Foundation

struct HistoryWishItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let itemType: String
    let rank: Int
    let iconUrl: URL?
    let count: Int
}

struct HistoryWishBanner: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let gachaType: String
    let bannerUrl: URL?
}

struct HistoryWishEvent: Identifiable, Equatable, Sendable {
    let id: String
    let version: String
    let name: String
    let gachaType: String
    let bannerUrl: URL?
    let banners: [HistoryWishBanner]
    let phaseTitle: String
    let startedAt: Date
    let endedAt: Date
    let total: Int
    let orangeUp: [HistoryWishItem]
    let purpleUp: [HistoryWishItem]
    let summary: [HistoryWishItem]
    let purple: [HistoryWishItem]
    let blue: [HistoryWishItem]

    var timeSpan: String {
        "\(Self.dayString(startedAt)) - \(Self.dayString(endedAt))"
    }

    var totalText: String { "总计 \(total) 抽" }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    private static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

extension String {
    var normalizedGachaType: String { self == "400" ? "301" : self }
}
