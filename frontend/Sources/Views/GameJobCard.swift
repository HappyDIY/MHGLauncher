import AppKit
import SwiftUI

struct GameJobCard: View {
    @Bindable var store: LauncherStore
    let job: GameJob
    @State private var tick = 0
    @State private var anchorBytes: Int64 = 0
    @State private var anchorTime = Date()

    private let ticker = Timer.publish(
        every: 0.2,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        GlassCard("资源任务", icon: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 10) {
                progressBar(smoothProgress)
                HStack {
                    Text(job.status.title)
                        .contentTransition(.opacity)
                    Spacer()
                    Text(smoothSizeLabel)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .motionAnimation(.selection, value: job.status)
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
                if !job.message.isEmpty {
                    Text(job.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .motionTransition(.emphasis)
                }
                if !job.activeChunks.isEmpty {
                    Divider()
                    ForEach(job.activeChunks) { chunk in
                        chunkProgress(chunk)
                    }
                }
                controls
            }
        }
        .onReceive(ticker) { _ in
            if job.status == .running { tick &+= 1 }
        }
        .onChange(of: job.completedBytes, initial: true) { _, value in
            anchorBytes = value
            anchorTime = Date()
        }
        .motionAnimation(.content, value: job.message)
        .motionAnimation(.content, value: job.activeChunks.map(\.id))
    }

    private func chunkProgress(_ chunk: ChunkProgress) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chunk.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            progressBar(smoothChunkProgress(chunk), tint: .blue)
                    .motionAnimation(.content, value: chunk.bytesDone)
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
            if [.pausing, .cancelling].contains(job.status) { ProgressView().controlSize(.small) }
        }
        .motionAnimation(.selection, value: job.status)
    }

    private var smoothProgress: Double {
        guard job.totalBytes > 0 else { return 0 }
        guard job.status == .running, job.downloadSpeed > 0 else {
            return job.progress
        }
        let predicted = Double(anchorBytes)
            + Double(job.downloadSpeed) * Date().timeIntervalSince(anchorTime)
        return min(predicted / Double(job.totalBytes), 1)
    }

    private var smoothSizeLabel: String {
        let current: Int64
        if job.status == .running, job.downloadSpeed > 0 {
            let predicted = Double(anchorBytes)
                + Double(job.downloadSpeed) * Date().timeIntervalSince(anchorTime)
            current = min(Int64(predicted), job.totalBytes)
        } else {
            current = job.completedBytes
        }
        let value = ByteCountFormatter.string(
            fromByteCount: current,
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: job.totalBytes,
            countStyle: .file
        )
        return "\(value) / \(total)"
    }

    private func smoothChunkProgress(_ chunk: ChunkProgress) -> Double {
        guard chunk.total > 0 else { return 0 }
        if job.status == .running,
           job.downloadSpeed > 0,
           chunk.bytesDone < chunk.total {
            let slots = max(Double(job.activeChunks.count), 1)
            let predicted = Double(chunk.bytesDone)
                + Double(job.downloadSpeed) / slots
                * Date().timeIntervalSince(anchorTime)
            return min(predicted / Double(chunk.total), 1)
        }
        return chunk.progress
    }

    private func progressBar(_ progress: Double, tint: Color = .accentColor) -> some View {
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
    }
}
