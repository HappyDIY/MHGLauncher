import SwiftUI

struct GameLaunchControls: View {
    @Bindable var store: LauncherStore
    @State private var confirmsStop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("性能模式", selection: $store.gamePerformanceProfile) {
                ForEach(GamePerformanceProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            Toggle("启动时显示 Metal HUD", isOn: $store.metalHudEnabled)
            Toggle("记录每一条 DNS 查询（网络调试）", isOn: $store.networkDebugEnabled)
            HStack {
                Button {
                    Task { await store.launchGame() }
                } label: {
                    if store.isLaunchingGame {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("启动游戏")
                    }
                }
                .contentTransition(.opacity)
                .buttonStyle(.borderedProminent)
                .disabled(store.installPath.isEmpty || launchIsActive || store.isLaunchingGame)
                if launchIsActive {
                    Button("停止游戏", role: .destructive) { confirmsStop = true }
                        .disabled(store.isStoppingGame)
                        .motionTransition(.selection)
                }
                if let launch = store.gameLaunch {
                    Label(launch.status.title, systemImage: launch.status.icon)
                        .font(.caption)
                        .foregroundStyle(launch.status == .failed ? .red : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .motionSymbolBounce(value: launch.status)
                        .motionTransition(.selection)
                }
            }
            if let message = store.gameLaunch?.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .motionTransition(.content)
            }
        }
        .motionAnimation(.selection, value: store.isLaunchingGame)
        .motionAnimation(.selection, value: store.gameLaunch?.status)
        .confirmationDialog("确定停止游戏？", isPresented: $confirmsStop, titleVisibility: .visible) {
            Button("停止游戏", role: .destructive) { Task { await store.stopGame() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("启动器将终止 Wine 会话并恢复临时修改的游戏文件。")
        }
    }

    private var launchIsActive: Bool {
        guard let status = store.gameLaunch?.status else { return false }
        return ![.stopped, .exited, .failed].contains(status)
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
        case .stopping: "正在停止游戏"
        case .stopped: "游戏已停止"
        case .exited: "游戏已退出"
        case .failed: "启动失败"
        }
    }

    var icon: String {
        switch self {
        case .running: "play.circle.fill"
        case .exited, .stopped: "checkmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        default: "hourglass"
        }
    }
}
