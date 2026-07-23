import AppKit
import SwiftUI

struct GameView: View {
    @Bindable var store: LauncherStore
    @State private var speedLimitTask: Task<Void, Never>?

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
                        Button {
                            revealInstallPath()
                        } label: {
                            Label("在 Finder 中显示", systemImage: "folder")
                        }
                        .buttonStyle(.glass)
                        .motionHover()
                        .disabled(!installPathExists)
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
                if let launch = store.gameLaunch {
                    GameLaunchProgressView(launch: launch)
                        .motionTransition(.emphasis)
                }
                GlassCard("游戏运行时", icon: "shippingbox") {
                    RuntimeStatusView(store: store)
                }
                .motionEntrance(order: 4)
                GlassCard("下载设置", icon: "arrow.down.circle") {
                    downloadSettings
                }
                .motionEntrance(order: 5)
                GameJobSection(store: store)
                GameResourceActionButtons(store: store)
                    .motionEntrance(order: 6)
                Spacer()
            }
            .motionAnimation(.emphasis, value: store.gameLaunch?.id)
            .task(id: store.installPath) {
                store.checkGameRuntime()
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await store.refreshGame()
            }
        }
        .onDisappear { speedLimitTask?.cancel() }
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

    private var installPathExists: Bool {
        let path = store.installPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }

    private func revealInstallPath() {
        let path = store.installPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private var updateSummary: String? {
        guard let state = store.gameState, state.status == .updateAvailable else {
            return nil
        }
        let kind = switch state.updateKind {
        case "game_hotfix": "游戏内热更新"
        case "package_repair": "启动器资源修复"
        case "version_diff", "version_diff_chunks": "版本差分"
        default: "完整更新"
        }
        let size = ByteCountFormatting.fileSize(state.downloadBytes ?? 0)
        return "\(kind) · \(size)"
    }

    private var downloadSettings: some View {
        HStack {
            Text("下载速度限制")
            Spacer()
            HStack(spacing: 4) {
                TextField(
                    "0",
                    value: speedLimitBinding,
                    format: .number
                        .grouping(.never)
                        .precision(.fractionLength(0...2))
                )
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("下载速度限制")
                .onSubmit {
                    scheduleSpeedLimitUpdate(max(0, store.speedLimitKB))
                }
                Text("MB/s")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var speedLimitBinding: Binding<Double> {
        Binding {
            Double(store.speedLimitKB) / 1024
        } set: { value in
            let normalizedKB = Int((max(0, value) * 1024).rounded())
            store.speedLimitKB = normalizedKB
            scheduleSpeedLimitUpdate(normalizedKB)
        }
    }

    private func scheduleSpeedLimitUpdate(_ value: Int) {
        speedLimitTask?.cancel()
        speedLimitTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await store.setSpeedLimit(value)
        }
    }
}
