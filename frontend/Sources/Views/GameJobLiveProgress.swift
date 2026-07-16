import SwiftUI

struct GameJobLiveProgress: View {
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
        ViewportRetainedContent {
            VStack(alignment: .leading, spacing: 10) {
                GameProgressBar(progress: smoothProgress, label: "资源任务总进度")
                HStack {
                    Text(job.status.title)
                        .contentTransition(.opacity)
                        .accessibilityLiveRegion(.polite)
                    Spacer()
                    Text(smoothSizeLabel)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .motionAnimation(.selection, value: job.status)
            }
            .onReceive(ticker) { _ in
                if job.status == .running { tick &+= 1 }
            }
        }
        .onChange(of: job.completedBytes, initial: true) { _, value in
            anchorBytes = value
            anchorTime = Date()
        }
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
}

struct GameJobLiveChunks: View {
    let job: GameJob
    @State private var tick = 0
    @State private var anchorTime = Date()

    private let ticker = Timer.publish(
        every: 0.2,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        ViewportRetainedContent(
            geometryID: AnyHashable(job.activeChunks.map(\.id))
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(job.activeChunks) { chunk in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chunk.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        GameProgressBar(
                            progress: smoothProgress(chunk),
                            tint: .blue,
                            label: "\(chunk.name) 进度"
                        )
                        .motionAnimation(.content, value: chunk.bytesDone)
                    }
                }
            }
            .onReceive(ticker) { _ in
                if job.status == .running { tick &+= 1 }
            }
        }
        .onChange(of: job.completedBytes, initial: true) { _, _ in
            anchorTime = Date()
        }
    }

    private func smoothProgress(_ chunk: ChunkProgress) -> Double {
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
}
