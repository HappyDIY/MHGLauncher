import Foundation
import Observation

@MainActor
@Observable
final class ValueStore {
    var gachaEvents: [GachaEvent] = []
    var achievementArchives: [AchievementArchive] = []
    var achievementGoals: [AchievementGoal] = []
    var achievementEntries: [AchievementEntry] = []
    var achievementRevision = 0
    var achievementIntent = 0
    var achievementLoaded = false
    var achievementError: String?
    var notificationSettings: NotificationSettings?
    var notificationError: String?
    var notificationEvents: [NotificationEvent] = []
    var cloudSession: CloudSession?
    var cloudLoginURL = ""
    var cloudMessage = ""
}
