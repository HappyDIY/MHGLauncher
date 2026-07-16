import SwiftUI

struct DownloadSpeedChart: View {
    let job: GameJobPresentation
    @State private var samples = SpeedSampleBuffer(capacity: 60)
    @State private var updatePhase = 0

    var body: some View {
        let speed = job.downloadSpeed
        let isActive = job.status == .running
        let sampleID = job.sampleID
        ViewportRetainedContent {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("下载速度")
                    Spacer()
                    Text(formatSpeed(speed))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .motionAnimation(.progress, value: sampleID)
                DownloadSpeedPlot(samples: samples)
                .motionAnimation(.progress, value: updatePhase)
            }
        }
        .onChange(of: sampleID, initial: true) { _, _ in
            guard isActive || speed > 0 else { return }
            samples.append(SpeedSample(time: Date(), bytesPerSecond: speed))
            updatePhase &+= 1
        }
    }

    private func formatSpeed(_ value: Int64) -> String {
        if value >= 1_048_576 { return String(format: "%.1f MB/s", Double(value) / 1_048_576) }
        if value >= 1_024 { return String(format: "%.0f KB/s", Double(value) / 1_024) }
        return "0 KB/s"
    }
}

struct SpeedSample: Identifiable {
    let time: Date
    let bytesPerSecond: Int64
    var id: Date { time }
    var megabytesPerSecond: Double { Double(bytesPerSecond) / 1_048_576 }
}

struct SpeedSampleBuffer: RandomAccessCollection {
    typealias Index = Int

    private let capacity: Int
    private var storage: [SpeedSample] = []
    private var writeIndex = 0

    init(capacity: Int) {
        self.capacity = Swift.max(capacity, 1)
        storage.reserveCapacity(self.capacity)
    }

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    subscript(position: Int) -> SpeedSample {
        precondition(indices.contains(position))
        guard storage.count == capacity else { return storage[position] }
        return storage[(writeIndex + position) % capacity]
    }

    mutating func append(_ sample: SpeedSample) {
        if storage.count < capacity {
            storage.append(sample)
            return
        }
        storage[writeIndex] = sample
        writeIndex = (writeIndex + 1) % capacity
    }
}
