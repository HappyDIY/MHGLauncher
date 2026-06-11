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
                    Text(store.gameState?.status.title ?? "检查中")
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
                Button("更新") {
                    Task { await store.startGameJob(.update) }
                }
                Spacer()
            }
            .buttonStyle(.glassProminent)
            Spacer()
        }
    }

    private func jobCard(_ job: GameJob) -> some View {
        GlassCard("资源任务", icon: "arrow.down.circle") {
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
}
