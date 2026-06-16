import AppKit
import SwiftUI

struct GameView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "游戏",
                subtitle: "管理国服 Windows 客户端资源"
            )
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
                    }
                    .foregroundStyle(.secondary)
                }
            }
            GlassCard("安装位置", icon: "folder") {
                HStack {
                    TextField("选择游戏目录", text: $store.installPath)
                    Button("选择") { chooseDirectory() }
                        .buttonStyle(.glass)
                }
            }
            if let job = store.gameJob {
                jobCard(job)
            }
            HStack {
                Button("安装") {
                    Task { await store.startGameJob(.install) }
                }
                .disabled(store.gameState?.status != .notInstalled)
                Button("更新") {
                    Task { await store.startGameJob(.update) }
                }
                .disabled(store.gameState?.status != .updateAvailable)
                Spacer()
            }
            .buttonStyle(.glassProminent)
            Spacer()
        }
        .task(id: store.installPath) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await store.refreshGame()
        }
    }

    private func jobCard(_ job: GameJob) -> some View {
        GlassCard("资源任务", icon: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: job.progress)
                HStack {
                    Text(job.status.title)
                    Spacer()
                    Text(
                        "\(ByteCountFormatter.string(fromByteCount: job.completedBytes, countStyle: .file)) / "
                        + ByteCountFormatter.string(fromByteCount: job.totalBytes, countStyle: .file)
                    )
                    .foregroundStyle(.secondary)
                }
                if job.downloadSpeed > 0 {
                    HStack {
                        Text(formatSpeed(job.downloadSpeed))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("分块 \(job.chunksCompleted) / \(job.chunksTotal)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                if !job.activeChunks.isEmpty {
                    Divider()
                    ForEach(job.activeChunks.prefix(4)) { chunk in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chunk.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            ProgressView(value: chunk.progress)
                                .tint(.blue)
                        }
                    }
                }
                HStack {
                    if job.status == .running {
                        Button("暂停") {
                            Task { await store.controlGameJob("pause") }
                        }
                    } else if job.status == .paused {
                        Button("继续") {
                            Task { await store.controlGameJob("resume") }
                        }
                    }
                    if [.running, .paused, .queued].contains(job.status) {
                        Button("取消", role: .destructive) {
                            Task { await store.controlGameJob("cancel") }
                        }
                    }
                }
            }
        }
    }

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        if bytesPerSec >= 1_048_576 {
            String(format: "%.1f MB/s", Double(bytesPerSec) / 1_048_576)
        } else if bytesPerSec >= 1_024 {
            String(format: "%.0f KB/s", Double(bytesPerSec) / 1_024)
        } else {
            "0 KB/s"
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
}
