import AppKit
import SwiftUI

struct GameJobCard: View {
    let store: LauncherStore
    let job: GameJobPresentation

    var body: some View {
        GlassCard("资源任务", icon: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 10) {
                GameJobLiveProgress(job: job)
                DownloadSpeedChart(job: job)
                GameJobChunkCount(job: job)
                GameJobMessage(job: job)
                GameJobChunkSection(job: job)
                GameJobControls(store: store, job: job)
            }
        }
        .motionAnimation(.content, value: job.message)
        .motionAnimation(.content, value: job.activeChunks.map(\.id))
    }

}

private struct GameJobChunkCount: View {
    let job: GameJobPresentation

    var body: some View {
        let counts = job.counts
        Text("分块 \(counts.completed) / \(counts.total)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .motionAnimation(.content, value: counts.completed)
    }
}

private struct GameJobMessage: View {
    let job: GameJobPresentation

    var body: some View {
        if !job.message.isEmpty {
            Text(job.message)
                .font(.caption)
                .foregroundStyle(.red)
                .motionTransition(.emphasis)
        }
    }
}

private struct GameJobChunkSection: View {
    let job: GameJobPresentation

    var body: some View {
        if !job.activeChunks.isEmpty {
            Divider()
            GameJobLiveChunks(job: job)
        }
    }
}

private struct GameJobControls: View {
    let store: LauncherStore
    let job: GameJobPresentation

    var body: some View {
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
    let store: LauncherStore

    var body: some View {
        Group {
            if store.gameJobPresentation.id != nil {
                GameJobCard(store: store, job: store.gameJobPresentation)
                    .motionTransition(.emphasis)
            }
        }
        .motionAnimation(.emphasis, value: store.gameJobPresentation.id)
    }
}
