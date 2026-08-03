import Foundation

extension LauncherStore {
    func loadNotificationSettings() async {
        do {
            let loaded = try await requireClient().notifications.settings()
            value.notificationSettings = loaded
            value.notificationConfirmedSettings = loaded
            value.notificationError = nil
        } catch {
            value.notificationError = Self.presentableMessage(error)
        }
    }

    func updateNotificationSettings(_ settings: NotificationSettings) async {
        do {
            let saved = try await requireClient().notifications.updateSettings(settings)
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

    func evaluateNotifications(silent: Bool = false) async {
        do {
            let events = try await requireClient().notifications.evaluate(selectedRole?.uid)
            value.notificationEvents = events
            let delivered = try await notifications.deliver(events)
            value.notificationPermissionMessage = nil
            guard !delivered.isEmpty else { return }
            _ = try await requireClient().notifications.acknowledge(delivered)
        } catch let error as UserNotificationDeliveryError {
            value.notificationPermissionMessage = error.localizedDescription
        } catch {
            if !silent { message = Self.presentableMessage(error) }
        }
    }
}
