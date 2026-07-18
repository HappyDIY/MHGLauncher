import SwiftUI

struct NotificationsView: View {
    @Bindable var store: LauncherStore
    @State private var updateTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "消息提醒", subtitle: "本机通知")
            GlassCard("MHGLauncher 更新", icon: "arrow.down.app") {
                LabeledContent("当前版本", value: store.currentAppVersion)
                if let manifest = store.appUpdate.manifest {
                    LabeledContent("可用版本", value: manifest.version)
                    Button {
                        store.appUpdate.showsSheet = true
                    } label: {
                        Label("查看更新", systemImage: "doc.text.magnifyingglass")
                    }
                }
                Button {
                    Task { await store.checkForAppUpdate() }
                } label: {
                    Label("检查更新", systemImage: "arrow.clockwise")
                }
                .disabled(store.appUpdate.isChecking || store.backend.client == nil)
            }
            if store.selectedRole == nil {
                ContentUnavailableView(
                    "需要选择角色",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("登录并选择角色后可配置便笺提醒。")
                )
            } else if let error = store.value.notificationError {
                ContentUnavailableView {
                    Label("无法载入提醒设置", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("重试") { Task { await store.loadValueData() } }
                }
                .accessibilityLiveRegion(.assertive)
            } else if store.value.notificationSettings == nil {
                ProgressView("正在载入提醒设置")
                    .accessibilityLiveRegion(.polite)
            } else {
                GlassCard("实时便笺", icon: "note.text") {
                    Toggle("每日委托", isOn: bool(\.dailyCommissionEnabled))
                    DatePicker(
                        "提醒时间",
                        selection: notificationTime,
                        displayedComponents: [.hourAndMinute]
                    )
                        .datePickerStyle(.compact)
                        .frame(width: 120)
                    Toggle("体力回满", isOn: bool(\.resinFullEnabled))
                }
                GlassCard("更新", icon: "bell.badge") {
                    Toggle("卡池刷新", isOn: bool(\.gachaRefreshEnabled))
                    Toggle("游戏版本更新", isOn: bool(\.versionUpdateEnabled))
                    Button {
                        Task { await store.evaluateNotifications() }
                    } label: {
                        Label("立即检查", systemImage: "bell")
                    }
                    .disabled(store.selectedRole == nil || store.isBusy)
                }
            }
            Spacer()
        }
        .task { await store.loadValueData() }
        .motionEntrance(.content)
    }

    private func bool(_ keyPath: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding {
            store.value.notificationSettings?[keyPath: keyPath] ?? false
        } set: { newValue in
            guard var settings = store.value.notificationSettings else { return }
            let previous = settings
            settings[keyPath: keyPath] = newValue
            store.value.notificationSettings = settings
            scheduleSettingsUpdate(settings, revertingTo: previous)
        }
    }

    private var notificationTime: Binding<Date> {
        Binding {
            let value = store.value.notificationSettings?.dailyCommissionTime ?? "00:00"
            let fields = value.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(
                bySettingHour: fields.first ?? 0,
                minute: fields.dropFirst().first ?? 0,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { newValue in
            guard var settings = store.value.notificationSettings else { return }
            let previous = settings
            let fields = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            settings.dailyCommissionTime = String(
                format: "%02d:%02d", fields.hour ?? 0, fields.minute ?? 0
            )
            store.value.notificationSettings = settings
            scheduleSettingsUpdate(settings, revertingTo: previous)
        }
    }

    private func scheduleSettingsUpdate(
        _ settings: NotificationSettings,
        revertingTo previous: NotificationSettings
    ) {
        updateTask?.cancel()
        updateTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await store.updateNotificationSettings(settings, revertingTo: previous)
        }
    }
}
