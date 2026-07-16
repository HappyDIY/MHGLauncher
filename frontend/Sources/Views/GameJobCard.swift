import AppKit
import SwiftUI

struct GameJobCard: View {
    @Bindable var store: LauncherStore
    let job: GameJob

    var body: some View {
        GlassCard("资源任务", icon: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 10) {
                GameJobLiveProgress(job: job)
                DownloadSpeedChart(
                    speed: job.downloadSpeed,
                    isActive: job.status == .running,
                    sampleID: job.lastUpdate ?? job.revision.map(String.init)
                )
                Text("分块 \(job.chunksCompleted) / \(job.chunksTotal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .motionAnimation(.content, value: job.chunksCompleted)
                Group {
                    if !job.message.isEmpty {
                        Text(job.message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .motionTransition(.emphasis)
                    }
                }
                .motionAnimation(.content, value: job.message)
                if !job.activeChunks.isEmpty {
                    Divider()
                    GameJobLiveChunks(job: job)
                }
                controls
            }
        }
    }

    private var controls: some View {
        HStack {
            if job.status == .running {
                Button("暂停") {
                    Task { await store.controlGameJob("pause") }
                }
                .motionHover()
                .motionTransition(.selection)
            } else if job.status == .paused {
                Button("继续") {
                    Task { await store.controlGameJob("resume") }
                }
                .motionHover(.prominent)
                .motionTransition(.selection)
            }
            if [.running, .paused, .queued].contains(job.status) {
                Button("取消", role: .destructive) {
                    Task { await store.controlGameJob("cancel") }
                }
                .motionHover(.destructive)
                .motionTransition(.selection)
            }
            if [.pausing, .cancelling].contains(job.status) {
                ProgressView(job.status.title).controlSize(.small)
            }
        }
        .motionAnimation(.selection, value: job.status)
    }

}

struct GameProgressBar: View {
    let progress: Double
    var tint: Color = .accentColor
    let label: String

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(width: max(geometry.size.width * progress, progress > 0.001 ? 4 : 0))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(progress * 100))%")
    }
}

struct GameJobSection: View {
    @Bindable var store: LauncherStore

    var body: some View {
        Group {
            if let job = store.gameJob {
                GameJobCard(store: store, job: job)
                    .motionTransition(.emphasis)
            }
        }
        .motionAnimation(.emphasis, value: store.gameJob?.id)
    }
}
