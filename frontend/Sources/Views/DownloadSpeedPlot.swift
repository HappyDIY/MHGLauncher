import SwiftUI

struct DownloadSpeedPlot: View, Animatable {
    private let sampleCount: Int
    var animatableData: SpeedPlotVector

    init(samples: SpeedSampleBuffer) {
        sampleCount = min(samples.count, SpeedPlotVector.capacity)
        animatableData = SpeedPlotVector(samples: samples)
    }

    var body: some View {
        DownloadSpeedPlotCanvas(
            vector: animatableData,
            count: sampleCount
        )
        .frame(height: 92)
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
