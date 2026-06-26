import AppKit
import SwiftUI

struct GameView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "游戏",
                    subtitle: "管理国服 Windows 客户端资源"
                )
                .motionEntrance(order: 0)
                GlassCard("安装状态", icon: "internaldrive") {
                    HStack {
                        MetricView(
                            value: store.gameState?.installedVersion.nonempty ?? "未安装",
                            label: "当前版本"
                        )
                        MetricView(
                            value: store.gameState?.availableVersion.nonempty ?? "未知",
                            label: "可用版本"
                        )
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(store.gameState?.status.title ?? "检查中")
                            if let update = updateSummary {
                                Text(update)
                                    .font(.caption)
                            }
                            if let preVersion = store.gameState?.predownloadVersion, !preVersion.isEmpty {
                                Text(store.gameState?.predownloadFinished == true ? "预下载完成 \(preVersion)" : "可预下载 \(preVersion)")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .motionEntrance(order: 1)
                GlassCard("安装位置", icon: "folder") {
                    HStack {
                        TextField("选择游戏目录", text: $store.installPath)
                        Button("选择") { chooseDirectory() }
                            .buttonStyle(.glass)
                            .motionHover()
                    }
                }
                .motionEntrance(order: 2)
                GlassCard("游戏启动", icon: "play.circle") {
                    GameLaunchControls(store: store)
                }
                .motionEntrance(order: 3)
                GlassCard("游戏运行时", icon: "shippingbox") {
                    RuntimeStatusView(store: store)
                }
                .motionEntrance(order: 4)
                GlassCard("下载设置", icon: "arrow.down.circle") {
                    downloadSettings
                }
                .motionEntrance(order: 5)
                if let launch = store.gameLaunch {
                    GameLaunchProgressView(launch: launch)
                        .motionTransition(.emphasis)
                }
                if let job = store.gameJob {
                    GameJobCard(store: store, job: job)
                        .motionTransition(.emphasis)
                }
                GameResourceActionButtons(store: store)
                    .motionEntrance(order: 6)
                Spacer()
            }
            .motionAnimation(.emphasis, value: store.gameLaunch?.id)
            .motionAnimation(.emphasis, value: store.gameJob?.id)
            .task(id: store.installPath) {
                store.checkGameRuntime()
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await store.refreshGame()
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK {
            store.installPath = panel.url?.path ?? ""
        }
    }

    private var updateSummary: String? {
        guard let state = store.gameState, state.status == .updateAvailable else {
            return nil
        }
        let kind = switch state.updateKind {
        case "game_hotfix": "游戏内热更新"
        case "package_repair": "启动器资源修复"
        case "version_diff": "版本差分"
        default: "完整更新"
        }
        let size = ByteCountFormatter.string(
            fromByteCount: state.downloadBytes ?? 0,
            countStyle: .file
        )
        return "\(kind) · \(size)"
    }

    private var downloadSettings: some View {
        HStack {
            Text("下载速度限制")
            Spacer()
            HStack(spacing: 4) {
                TextField(
                    "0",
                    value: $store.speedLimitKB,
                    format: .number.grouping(.never)
                )
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                .onSubmit {
                    let value = max(0, store.speedLimitKB)
                    store.speedLimitKB = value
                    Task { await store.setSpeedLimit(value) }
                }
                Text("KB/s")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
