import SwiftUI

struct GameLaunchControls: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("性能模式", selection: $store.gamePerformanceProfile) {
                ForEach(GamePerformanceProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            Toggle("启动时显示 Metal HUD", isOn: $store.metalHudEnabled)
            HStack {
                Button("启动游戏") {
                    Task { await store.launchGame() }
                }
                .buttonStyle(.glassProminent)
                .disabled(store.installPath.isEmpty || launchIsActive)
                if let launch = store.gameLaunch {
                    Label(launch.status.title, systemImage: launch.status.icon)
                        .font(.caption)
                        .foregroundStyle(launch.status == .failed ? .red : .secondary)
                }
            }
            if let message = store.gameLaunch?.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var launchIsActive: Bool {
        guard let status = store.gameLaunch?.status else { return false }
        return ![.exited, .failed].contains(status)
    }
}

extension GamePerformanceProfile {
    var title: String {
        switch self {
        case .optimized: "MSync 优化"
        case .compatibility: "ESync 兼容"
        case .baseline: "基础模式"
        }
    }
}

extension GameLaunchStatus {
    var title: String {
        switch self {
        case .preparing: "正在校验文件"
        case .starting: "正在启动 Wine"
        case .waitingWindow: "等待游戏窗口"
        case .running: "游戏运行中"
        case .exited: "游戏已退出"
        case .failed: "启动失败"
        }
    }

    var icon: String {
        switch self {
        case .running: "play.circle.fill"
        case .exited: "checkmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        default: "hourglass"
        }
    }
}
