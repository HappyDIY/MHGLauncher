import Foundation
import Observation

@MainActor
@Observable
final class ValueStore {
    var characters: [GameCharacter] = []
    var gachaEvents: [GachaEvent] = []
    var achievementArchives: [AchievementArchive] = []
    var achievements: [AchievementItem] = []
    var notificationSettings: NotificationSettings?
    var notificationEvents: [NotificationEvent] = []
    var cloudSession: CloudSession?
    var cloudLoginURL = ""
    var cloudMessage = ""
    var achievementDraftId = ""
    var achievementDraftCurrent = 1
    var achievementDraftStatus = 2
    var cycles: [CycleKind: [CycleRecord]] = [:]

    func records(for kind: CycleKind) -> [CycleRecord] {
        cycles[kind] ?? []
    }
}
