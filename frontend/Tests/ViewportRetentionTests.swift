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
}
