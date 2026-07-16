import Charts
import SwiftUI

struct DownloadSpeedChart: View {
    let speed: Int64
    let isActive: Bool
    let sampleID: String?
    @State private var samples = SpeedSampleBuffer(capacity: 60)
    @State private var updatePhase = 0

    var body: some View {
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
                Chart(samples.values) { sample in
                    AreaMark(
                        x: .value("时间", sample.time),
                        y: .value("速度", sample.megabytesPerSecond)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.18), .blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("时间", sample.time),
                        y: .value("速度", sample.megabytesPerSecond)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.0f MB/s", number))
                            }
                        }
                    }
                }
                .frame(height: 92)
                .motionAnimation(.progress, value: updatePhase)
            }
        }
        .motionAnimation(.progress, value: sampleID)
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

struct SpeedSampleBuffer {
    private let capacity: Int
    private var storage: [SpeedSample] = []
    private var writeIndex = 0

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
        storage.reserveCapacity(self.capacity)
    }

    var values: [SpeedSample] {
        guard storage.count == capacity, writeIndex > 0 else { return storage }
        return Array(storage[writeIndex...]) + storage[..<writeIndex]
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
