import CoreGraphics
import Foundation
import Testing
@testable import MHGLauncher

@Suite("下载进度可见性管理")
struct ViewportRetentionTests {
    @Test("首次测量前始终构建内容")
    func keepsContentUntilMeasured() {
        var state = ViewportRetentionState()

        state.updateVisibility(false)

        #expect(state.shouldRender)
    }

    @Test("离开可见区后使用等高占位")
    func evictsMeasuredContentWhenHidden() {
        var state = ViewportRetentionState()
        state.updateHeight(148)

        state.updateVisibility(false)

        #expect(!state.shouldRender)
        #expect(state.retainedHeight == 148)
    }

    @Test("重新进入可见区时恢复内容")
    func restoresContentWhenVisible() {
        var state = ViewportRetentionState()
        state.updateHeight(148)
        state.updateVisibility(false)

        state.updateVisibility(true)

        #expect(state.shouldRender)
        #expect(state.retainedHeight == 148)
    }

    @Test("隐藏期间结构变化仅重新测量一次")
    func invalidatesHeightForStructuralChange() {
        var state = ViewportRetentionState()
        state.updateHeight(148)
        state.updateVisibility(false)

        state.invalidateMeasurement()

        #expect(state.shouldRender)
        state.updateHeight(196)
        #expect(!state.shouldRender)
        #expect(state.retainedHeight == 196)
    }

    @Test("非激活页在测得高度后停止构建高频内容")
    func inactivePageStopsRenderingAfterMeasurement() {
        var state = ViewportRetentionState()
        state.updateHeight(148)

        // 页面不可见（非激活）时以占位替代，停止内部计时器与重绘。
        #expect(!state.shouldRender(pageActive: false))
        // 激活页仍按滚动可见性构建。
        #expect(state.shouldRender(pageActive: true))
    }

    @Test("非激活页在首次测量前仍构建以获取占位高度")
    func inactivePageStillBuildsBeforeMeasurement() {
        let state = ViewportRetentionState()

        #expect(state.shouldRender(pageActive: false))
    }

    @Test("激活页离开可视区后同样使用占位")
    func activePageEvictsWhenScrolledAway() {
        var state = ViewportRetentionState()
        state.updateHeight(148)
        state.updateVisibility(false)

        #expect(!state.shouldRender(pageActive: true))
    }

    @Test("速度样本环形缓冲区保留最新项与时间顺序")
    func speedBufferRetainsNewestSamples() {
        var buffer = SpeedSampleBuffer(capacity: 3)
        let start = Date(timeIntervalSince1970: 1_000)

        for value in 1...5 {
            buffer.append(SpeedSample(
                time: start.addingTimeInterval(Double(value)),
                bytesPerSecond: Int64(value)
            ))
        }

        #expect(buffer.map(\.bytesPerSecond) == [3, 4, 5])
    }

    @Test("速度动画向量使用固定内存")
    func speedPlotVectorHasFixedCapacity() {
        var buffer = SpeedSampleBuffer(capacity: 60)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        for value in 1...100 {
            buffer.append(SpeedSample(
                time: start.addingTimeInterval(Double(value)),
                bytesPerSecond: Int64(value)
            ))
        }

        let vector = SpeedPlotVector(samples: buffer)

        #expect(vector.times.scalarCount == 64)
        #expect(vector.speeds.scalarCount == 64)
        #expect(vector.speeds[0] == 41)
        #expect(vector.speeds[59] == 100)
    }
}
