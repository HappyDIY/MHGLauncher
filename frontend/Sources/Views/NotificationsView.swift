import SwiftUI

struct NotificationsView: View {
    @Bindable var store: LauncherStore
    @State private var updateTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "消息提醒", subtitle: "本机通知")
            if store.value.notificationSettings == nil {
                ProgressView()
            } else {
                GlassCard("实时便笺", icon: "note.text") {
                    Toggle("每日委托", isOn: bool(\.dailyCommissionEnabled))
                    TextField("提醒时间", text: text(\.dailyCommissionTime))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Toggle("体力回满", isOn: bool(\.resinFullEnabled))
                }
                GlassCard("周期", icon: "calendar") {
                    Toggle("深渊刷新", isOn: bool(\.abyssRefreshEnabled))
                    Toggle("剧诗刷新", isOn: bool(\.theatreRefreshEnabled))
                    Toggle("危战刷新", isOn: bool(\.hardRefreshEnabled))
                }
                GlassCard("更新", icon: "bell.badge") {
                    Toggle("卡池刷新", isOn: bool(\.gachaRefreshEnabled))
                    Toggle("版本更新", isOn: bool(\.versionUpdateEnabled))
                    Button {
                        Task { await store.evaluateNotifications() }
                    } label: {
                        Label("立即检查", systemImage: "bell")
                    }
                }
            }
            Spacer()
        }
        .task { await store.loadValueData() }
        .onDisappear { updateTask?.cancel() }
        .motionEntrance(.content)
    }

    private func bool(_ keyPath: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding {
            store.value.notificationSettings?[keyPath: keyPath] ?? false
        } set: { newValue in
            guard var settings = store.value.notificationSettings else { return }
            settings[keyPath: keyPath] = newValue
            store.value.notificationSettings = settings
            scheduleSettingsUpdate(settings)
        }
    }

    private func text(_ keyPath: WritableKeyPath<NotificationSettings, String>) -> Binding<String> {
        Binding {
            store.value.notificationSettings?[keyPath: keyPath] ?? ""
        } set: { newValue in
            guard var settings = store.value.notificationSettings else { return }
            settings[keyPath: keyPath] = newValue
            store.value.notificationSettings = settings
            scheduleSettingsUpdate(settings)
        }
    }

    private func scheduleSettingsUpdate(_ settings: NotificationSettings) {
        updateTask?.cancel()
        updateTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await store.updateNotificationSettings(settings)
        }
    }
}
