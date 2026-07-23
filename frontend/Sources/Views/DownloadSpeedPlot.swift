import Charts
import SwiftUI

struct DownloadSpeedPlot: View, Animatable {
    private let sampleCount: Int
    var animatableData: SpeedPlotVector

    init(samples: SpeedSampleBuffer) {
        sampleCount = min(samples.count, SpeedPlotVector.capacity)
        animatableData = SpeedPlotVector(samples: samples)
    }

    var body: some View {
        let data = SpeedPlotData(vector: animatableData, count: sampleCount)
        Chart {
            AreaPlot(
                data,
                x: .value("时间", \.time),
                y: .value("速度", \.megabytesPerSecond)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.accentColor.opacity(0.18), .accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LinePlot(
                data,
                x: .value("时间", \.time),
                y: .value("速度", \.megabytesPerSecond)
            )
            .foregroundStyle(Color.accentColor)
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
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

struct SpeedPlotVector: VectorArithmetic {
    static let capacity = 60
    var times = SIMD64<Double>(repeating: 0)
    var speeds = SIMD64<Double>(repeating: 0)

    init() {}

    init(samples: SpeedSampleBuffer) {
        var lastTime = 0.0
        var lastSpeed = 0.0
        for index in 0..<Self.capacity {
            if index < samples.count {
                let sample = samples[index]
                lastTime = sample.time.timeIntervalSinceReferenceDate
                lastSpeed = Double(sample.bytesPerSecond)
            }
            times[index] = lastTime
            speeds[index] = lastSpeed
        }
    }

    static var zero: SpeedPlotVector { SpeedPlotVector() }

    static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result += rhs
        return result
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result -= rhs
        return result
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs.times += rhs.times
        lhs.speeds += rhs.speeds
    }

    static func -= (lhs: inout Self, rhs: Self) {
        lhs.times -= rhs.times
        lhs.speeds -= rhs.speeds
    }

    mutating func scale(by rhs: Double) {
        times *= rhs
        speeds *= rhs
    }

    var magnitudeSquared: Double {
        var result = 0.0
        for index in 0..<Self.capacity {
            result += times[index] * times[index]
            result += speeds[index] * speeds[index]
        }
        return result
    }
}

private struct SpeedPlotPoint {
    let time: Date
    let megabytesPerSecond: Double
}

private struct SpeedPlotData: RandomAccessCollection {
    let vector: SpeedPlotVector
    let count: Int
    var startIndex: Int { 0 }
    var endIndex: Int { count }

    subscript(position: Int) -> SpeedPlotPoint {
        SpeedPlotPoint(
            time: Date(timeIntervalSinceReferenceDate: vector.times[position]),
            megabytesPerSecond: vector.speeds[position] / 1_048_576
        )
    }
}
