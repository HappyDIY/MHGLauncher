import Foundation
import UserNotifications

struct UserNotificationService: Sendable {
    func deliver(_ events: [NotificationEvent]) async throws {
        guard !events.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            content.userInfo = ["destination": event.destination]
            let request = UNNotificationRequest(
                identifier: event.key,
                content: content,
                trigger: nil
            )
            try await center.add(request)
        }
    }
}
