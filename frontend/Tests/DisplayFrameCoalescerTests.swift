import Foundation
import Testing
@testable import MHGLauncher

@MainActor
@Suite("显示帧进度合并")
struct DisplayFrameCoalescerTests {
    @Test("同一显示帧只提交最新值")
    func presentsLatestValueOncePerFrame() {
        let scheduler = TestDisplayFrameScheduler()
        var presented: [Int] = []
        let coalescer = makeCoalescer(scheduler, presented: { presented.append($0) })

        for value in 0..<10_000 {
            coalescer.submit(value, at: 0)
        }

        #expect(scheduler.pendingCount == 1)
        #expect(scheduler.scheduleCount == 1)
        scheduler.fire(at: 0)
        #expect(presented == [9_999])

        for value in 10_000..<20_000 {
            coalescer.submit(value, at: 0.01)
        }
        #expect(scheduler.pendingCount == 1)
        #expect(scheduler.scheduleCount == 2)
        scheduler.fire(at: 0.19)
        #expect(presented == [9_999])
        scheduler.fire(at: 0.2)
        #expect(presented == [9_999, 19_999])
    }

    @Test("终态刷新立即提交且不会重复")
    func flushesPendingValueOnce() {
        let scheduler = TestDisplayFrameScheduler()
        var presented: [Int] = []
        let coalescer = makeCoalescer(scheduler, presented: { presented.append($0) })

        coalescer.submit(1)
        coalescer.submit(2)
        coalescer.flush()

        #expect(presented == [2])
        #expect(scheduler.pendingCount == 0)
        scheduler.fire(at: 1)
        #expect(presented == [2])
    }

    @Test("过期任务取消时丢弃待提交值")
    func cancelsPendingValue() {
        let scheduler = TestDisplayFrameScheduler()
        var presented: [Int] = []
        let coalescer = makeCoalescer(scheduler, presented: { presented.append($0) })

        coalescer.submit(1)
        coalescer.cancel()
        scheduler.fire(at: 1)

        #expect(presented.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test("语义变化提前到下一显示帧")
    func advancesPriorityChanges() {
        let scheduler = TestDisplayFrameScheduler()
        var presented: [Int] = []
        let coalescer = LatestDisplayFrameCoalescer(
            scheduler: scheduler,
            minimumInterval: 0.2,
            priority: { $0 / 100 },
            present: { presented.append($0) }
        )

        coalescer.submit(1, at: 0)
        scheduler.fire(at: 0)
        coalescer.submit(2, at: 0.01)
        coalescer.submit(100, at: 0.02)

        #expect(scheduler.deadline == 0.02)
        scheduler.fire(at: 0.02)
        #expect(presented == [1, 100])
    }

    private func makeCoalescer(
        _ scheduler: TestDisplayFrameScheduler,
        presented: @escaping (Int) -> Void
    ) -> LatestDisplayFrameCoalescer<Int, Int> {
        LatestDisplayFrameCoalescer(
            scheduler: scheduler,
            minimumInterval: 0.2,
            priority: { _ in 0 },
            present: presented
        )
    }
}

@MainActor
private final class TestDisplayFrameScheduler: DisplayFrameScheduling {
    private var action: DisplayFrameAction?
    private(set) var deadline: CFTimeInterval?
    var pendingCount: Int { action == nil ? 0 : 1 }
    private(set) var scheduleCount = 0

    func schedule(
        notBefore deadline: CFTimeInterval,
        _ action: @escaping DisplayFrameAction
    ) {
        scheduleCount += 1
        self.deadline = min(self.deadline ?? deadline, deadline)
        self.action = action
    }

    func cancel() {
        action = nil
        deadline = nil
    }

    func fire(at timestamp: CFTimeInterval) {
        guard timestamp >= (deadline ?? timestamp) else { return }
        let current = action
        action = nil
        deadline = nil
        current?(timestamp)
    }
}
