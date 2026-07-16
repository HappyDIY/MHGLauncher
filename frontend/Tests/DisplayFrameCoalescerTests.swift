import Testing
@testable import MHGLauncher

@MainActor
@Suite("显示帧进度合并")
struct DisplayFrameCoalescerTests {
    @Test("同一显示帧只提交最新值")
    func presentsLatestValueOncePerFrame() {
        let scheduler = TestDisplayFrameScheduler()
        var presented: [Int] = []
        let coalescer = LatestDisplayFrameCoalescer<Int>(scheduler: scheduler) {
            presented.append($0)
        }

        coalescer.submit(1)
        coalescer.submit(2)
        coalescer.submit(3)

        #expect(scheduler.pendingCount == 1)
        scheduler.fire()
        #expect(presented == [3])

        coalescer.submit(4)
        #expect(scheduler.pendingCount == 1)
        scheduler.fire()
        #expect(presented == [3, 4])
    }

    @Test("终态刷新立即提交且不会重复")
    func flushesPendingValueOnce() {
        let scheduler = TestDisplayFrameScheduler()
        var presented: [Int] = []
        let coalescer = LatestDisplayFrameCoalescer<Int>(scheduler: scheduler) {
            presented.append($0)
        }

        coalescer.submit(1)
        coalescer.submit(2)
        coalescer.flush()

        #expect(presented == [2])
        #expect(scheduler.pendingCount == 0)
        scheduler.fire()
        #expect(presented == [2])
    }

    @Test("过期任务取消时丢弃待提交值")
    func cancelsPendingValue() {
        let scheduler = TestDisplayFrameScheduler()
        var presented: [Int] = []
        let coalescer = LatestDisplayFrameCoalescer<Int>(scheduler: scheduler) {
            presented.append($0)
        }

        coalescer.submit(1)
        coalescer.cancel()
        scheduler.fire()

        #expect(presented.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }
}

@MainActor
private final class TestDisplayFrameScheduler: DisplayFrameScheduling {
    private var action: DisplayFrameAction?
    var pendingCount: Int { action == nil ? 0 : 1 }

    func schedule(_ action: @escaping DisplayFrameAction) {
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func fire() {
        let current = action
        action = nil
        current?()
    }
}
