import Charts
import SwiftUI

struct DownloadSpeedChart: View {
    let speed: Int64
    let isActive: Bool
    let sampleID: String?
    @State private var history = DownloadSpeedHistory()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("下载速度")
                Spacer()
                Text(formatSpeed(speed))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .motionAnimation(.progress, value: speed)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Chart(history.samples) { sample in
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
            .motionAnimation(.progress, value: history.revision)
        }
        .onChange(of: sampleID, initial: true) { _, _ in
            guard isActive || speed > 0 else { return }
            history.append(speed: speed, at: Date())
        }
    }

    private func formatSpeed(_ value: Int64) -> String {
        if value >= 1_048_576 { return String(format: "%.1f MB/s", Double(value) / 1_048_576) }
        if value >= 1_024 { return String(format: "%.0f KB/s", Double(value) / 1_024) }
        return "0 KB/s"
    }
}

private struct DownloadSpeedHistory {
    private(set) var samples: [SpeedSample] = []
    private(set) var revision = 0

    mutating func append(speed: Int64, at date: Date) {
        samples.append(SpeedSample(time: date, bytesPerSecond: speed))
        if samples.count > 60 {
            samples.removeFirst(samples.count - 60)
        }
        revision &+= 1
    }
}

private struct SpeedSample: Identifiable {
    let time: Date
    let bytesPerSecond: Int64
    var id: Date { time }
    var megabytesPerSecond: Double { Double(bytesPerSecond) / 1_048_576 }
}
