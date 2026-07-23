import Foundation

extension LauncherStore {
    func loadNotificationSettings() async {
        do {
            let loaded: NotificationSettings = try await requireClient().get(
                "/v1/notifications/settings"
            )
            value.notificationSettings = loaded
            value.notificationConfirmedSettings = loaded
            value.notificationError = nil
        } catch {
            value.notificationError = Self.presentableMessage(error)
        }
    }

    func updateNotificationSettings(_ settings: NotificationSettings) async {
        do {
            let saved: NotificationSettings = try await requireClient().put(
                "/v1/notifications/settings", body: settings
            )
            guard value.notificationSettings == settings else { return }
            value.notificationSettings = saved
            value.notificationConfirmedSettings = saved
            value.notificationError = nil
        } catch {
            guard value.notificationSettings == settings else { return }
            value.notificationSettings = value.notificationConfirmedSettings
            value.notificationError = Self.presentableMessage(error)
        }
    }

    func evaluateNotifications() async {
        do {
            var path = "/v1/notifications/evaluate"
            if let uid = selectedRole?.uid { path += "?uid=\(uid)" }
            let events: [NotificationEvent] = try await requireClient().post(path)
            value.notificationEvents = events
            let delivered = try await UserNotificationService().deliver(events)
            value.notificationPermissionMessage = nil
            guard !delivered.isEmpty else { return }
            let _: [String] = try await requireClient().post(
                "/v1/notifications/acknowledge",
                body: NotificationAcknowledgement(keys: delivered)
            )
        } catch let error as UserNotificationDeliveryError {
            value.notificationPermissionMessage = error.localizedDescription
        } catch {
            message = Self.presentableMessage(error)
        }
    }
}
