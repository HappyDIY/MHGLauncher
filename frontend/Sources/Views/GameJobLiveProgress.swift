import Observation
import SwiftUI

struct GameJobLiveProgress: View {
    let job: GameJobPresentation
    @State private var tick = 0
    @State private var anchorBytes: Int64 = 0
    @State private var anchorTime = Date()

    private let ticker = Timer.publish(
        every: 0.2,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        let progress = job.progress
        let status = job.status
        let speed = job.downloadSpeed
        ViewportRetainedContent {
            VStack(alignment: .leading, spacing: 10) {
                GameProgressBar(
                    progress: smoothProgress(progress, status: status, speed: speed),
                    label: "资源任务总进度"
                )
                HStack {
                    Text(status.title)
                        .contentTransition(.opacity)
                        .accessibilityLiveRegion(.polite)
                    Spacer()
                    Text(smoothSizeLabel(progress, status: status, speed: speed))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .motionAnimation(.selection, value: status)
            }
            .onReceive(ticker) { _ in
                if status == .running { tick &+= 1 }
            }
        }
        .onChange(of: progress.completedBytes, initial: true) { _, value in
            anchorBytes = value
            anchorTime = Date()
        }
    }

    private func smoothProgress(
        _ progress: GameJobProgressPresentation,
        status: JobStatus,
        speed: Int64
    ) -> Double {
        guard progress.totalBytes > 0 else { return 0 }
        guard status == .running, speed > 0 else {
            return Double(progress.completedBytes) / Double(progress.totalBytes)
        }
        let predicted = Double(anchorBytes)
            + Double(speed) * Date().timeIntervalSince(anchorTime)
        return min(predicted / Double(progress.totalBytes), 1)
    }

    private func smoothSizeLabel(
        _ progress: GameJobProgressPresentation,
        status: JobStatus,
        speed: Int64
    ) -> String {
        let current: Int64
        if status == .running, speed > 0 {
            let predicted = Double(anchorBytes)
                + Double(speed) * Date().timeIntervalSince(anchorTime)
            current = min(Int64(predicted), progress.totalBytes)
        } else {
            current = progress.completedBytes
        }
        let value = ByteCountFormatter.string(
            fromByteCount: current,
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: progress.totalBytes,
            countStyle: .file
        )
        return "\(value) / \(total)"
    }
}

struct GameJobLiveChunks: View {
    let job: GameJobPresentation
    @State private var clock = GameJobChunkClock()

    var body: some View {
        let chunks = job.activeChunks
        ViewportRetainedContent(
            geometryID: AnyHashable(chunks.map(\.id))
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(chunks) { chunk in
                    GameJobLiveChunkRow(job: job, chunk: chunk, clock: clock)
                }
            }
            .background {
                GameJobChunkClockDriver(job: job, clock: clock)
            }
        }
    }
}

@MainActor
@Observable
private final class GameJobChunkClock {
    var tick = 0
    var anchorTime = Date()
}

private struct GameJobChunkClockDriver: View {
    let job: GameJobPresentation
    let clock: GameJobChunkClock
    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(ticker) { _ in
                if job.status == .running { clock.tick &+= 1 }
            }
            .onChange(of: job.progress.completedBytes, initial: true) {
                clock.anchorTime = Date()
            }
    }
}

private struct GameJobLiveChunkRow: View {
    let job: GameJobPresentation
    let chunk: GameJobChunkPresentation
    let clock: GameJobChunkClock

    var body: some View {
        let progress = smoothProgress
        VStack(alignment: .leading, spacing: 3) {
            Text(chunk.id)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            GameProgressBar(
                progress: progress,
                tint: .blue,
                label: "\(chunk.id) 进度"
            )
            .motionAnimation(.content, value: chunk.bytesDone)
        }
    }

    private var smoothProgress: Double {
        _ = clock.tick
        guard chunk.total > 0 else { return 0 }
        if job.status == .running,
           job.downloadSpeed > 0,
           chunk.bytesDone < chunk.total {
            let slots = max(Double(job.activeChunks.count), 1)
            let predicted = Double(chunk.bytesDone)
                + Double(job.downloadSpeed) / slots
                * Date().timeIntervalSince(clock.anchorTime)
            return min(predicted / Double(chunk.total), 1)
        }
        return chunk.progress
    }
}
