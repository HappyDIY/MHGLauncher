import SwiftUI
import Testing
@testable import MHGLauncher

@MainActor
@Suite("下载速度绘制")
struct DownloadSpeedPlotTests {
    @Test("Canvas 绘制空值单值与曲线")
    func rendersPlotStates() {
        let empty = SpeedPlotVector()
        #expect(render(vector: empty, count: 0) != nil)

        var single = empty
        single.times[0] = 1
        single.speeds[0] = 1_048_576
        #expect(render(vector: single, count: 1) != nil)

        var curve = single
        curve.times[1] = 2
        curve.times[2] = 3
        curve.speeds[1] = 3_145_728
        curve.speeds[2] = 2_097_152
        #expect(render(vector: curve, count: 3) != nil)
    }

    @Test("布局限制数量并生成有限坐标")
    func resolvesPlotLayout() {
        var vector = SpeedPlotVector()
        for index in 0..<SpeedPlotVector.capacity {
            vector.times[index] = Double(index)
            vector.speeds[index] = Double(index + 1) * 1_048_576
        }
        let layout = SpeedPlotLayout(
            vector: vector,
            count: SpeedPlotVector.capacity + 10,
            size: CGSize(width: 420, height: 92)
        )

        #expect(layout.points.count == SpeedPlotVector.capacity)
        #expect(layout.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(layout.maximumMegabytes == 60)
        #expect(SpeedPlotLayout.axisMaximum(0) == 1)
        #expect(SpeedPlotLayout.axisMaximum(12) == 20)
    }

    @Test("曲线路径兼容空点单点与端点")
    func buildsCurvePaths() {
        #expect(DownloadSpeedPlotCanvas.curvePath([]).isEmpty)
        #expect(!DownloadSpeedPlotCanvas.curvePath([CGPoint(x: 1, y: 1)]).isEmpty)
        let points = [
            CGPoint(x: 0, y: 2),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 2, y: 1)
        ]
        #expect(!DownloadSpeedPlotCanvas.curvePath(points).isEmpty)
    }

    @Test("固定向量完整实现向量运算")
    func vectorArithmetic() {
        var first = SpeedPlotVector()
        first.times[0] = 2
        first.speeds[0] = 4
        var second = SpeedPlotVector()
        second.times[0] = 1
        second.speeds[0] = 2

        #expect((first + second).times[0] == 3)
        #expect((first - second).speeds[0] == 2)
        first += second
        first -= second
        first.scale(by: 0.5)
        #expect(first.times[0] == 1)
        #expect(first.magnitudeSquared == 5)
        #expect(SpeedPlotVector.zero.magnitudeSquared == 0)
    }

    private func render(vector: SpeedPlotVector, count: Int) -> NSImage? {
        ImageRenderer(
            content: DownloadSpeedPlotCanvas(vector: vector, count: count)
                .frame(width: 420, height: 92)
        ).nsImage
    }
}
