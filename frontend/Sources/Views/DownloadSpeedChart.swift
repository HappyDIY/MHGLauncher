import Charts
import SwiftUI

struct DownloadSpeedChart: View {
    let speed: Int64
    let isActive: Bool
    let sampleID: String?
    @State private var samples: [SpeedSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("下载速度")
                Spacer()
                Text(formatSpeed(speed))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Chart(samples) { sample in
                AreaMark(
                    x: .value("时间", sample.time),
                    y: .value("速度", sample.megabytesPerSecond)
                )
                .foregroundStyle(.blue.opacity(0.12))
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
        }
        .onChange(of: sampleID, initial: true) { _, _ in
            guard isActive || speed > 0 else { return }
            samples.append(SpeedSample(time: Date(), bytesPerSecond: speed))
            samples = Array(samples.suffix(60))
        }
    }

    private func formatSpeed(_ value: Int64) -> String {
        if value >= 1_048_576 { return String(format: "%.1f MB/s", Double(value) / 1_048_576) }
        if value >= 1_024 { return String(format: "%.0f KB/s", Double(value) / 1_024) }
        return "0 KB/s"
    }
}

private struct SpeedSample: Identifiable {
    let time: Date
    let bytesPerSecond: Int64
    var id: Date { time }
    var megabytesPerSecond: Double { Double(bytesPerSecond) / 1_048_576 }
}
