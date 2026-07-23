import Foundation
import UserNotifications

enum UserNotificationDeliveryError: LocalizedError, Sendable {
    case permissionDenied

    var errorDescription: String? {
        "系统通知权限未开启，请在“系统设置 > 通知”中允许 MHGLauncher 发送通知。"
    }
}

protocol UserNotificationDelivering: Sendable {
    func deliver(_ events: [NotificationEvent]) async throws -> [String]
}

struct UserNotificationService: UserNotificationDelivering {
    func deliver(_ events: [NotificationEvent]) async throws -> [String] {
        guard !events.isEmpty else { return [] }
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw UserNotificationDeliveryError.permissionDenied }
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
        return events.map(\.key)
    }
}
