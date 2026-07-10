import Foundation
import Observation

@MainActor
@Observable
final class ValueStore {
    var gachaEvents: [GachaEvent] = []
    var achievementArchives: [AchievementArchive] = []
    var achievementGoals: [AchievementGoal] = []
    var achievementEntries: [AchievementEntry] = []
    var notificationSettings: NotificationSettings?
    var notificationEvents: [NotificationEvent] = []
    var cloudSession: CloudSession?
    var cloudLoginURL = ""
    var cloudMessage = ""
}
