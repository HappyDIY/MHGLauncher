import AppKit
import QuartzCore

typealias DisplayFrameAction = @MainActor (CFTimeInterval) -> Void

@MainActor
protocol DisplayFrameScheduling: AnyObject {
    func schedule(
        notBefore deadline: CFTimeInterval,
        _ action: @escaping DisplayFrameAction
    )
    func cancel()
}

@MainActor
final class LatestDisplayFrameCoalescer<Value, Priority: Equatable> {
    private let scheduler: any DisplayFrameScheduling
    private let minimumInterval: CFTimeInterval
    private let priority: (Value) -> Priority
    private let present: (Value) -> Void
    private var pendingValue: Value?
    private var pendingPriority: Priority?
    private var lastPriority: Priority?
    private var lastPresentationTime: CFTimeInterval?
    private var frameScheduled = false

    init(
        scheduler: any DisplayFrameScheduling,
        minimumInterval: CFTimeInterval,
        priority: @escaping (Value) -> Priority,
        present: @escaping (Value) -> Void
    ) {
        self.scheduler = scheduler
        self.minimumInterval = minimumInterval
        self.priority = priority
        self.present = present
    }

    func submit(_ value: Value, at time: CFTimeInterval = CACurrentMediaTime()) {
        let nextPriority = priority(value)
        let previousPriority = pendingPriority ?? lastPriority
        let needsImmediateFrame = previousPriority != nextPriority
        pendingValue = value
        pendingPriority = nextPriority
        if frameScheduled, !needsImmediateFrame { return }
        let deadline = needsImmediateFrame
            ? time
            : max(time, (lastPresentationTime ?? time) + minimumInterval)
        frameScheduled = true
        scheduler.schedule(notBefore: deadline) { [weak self] timestamp in
            self?.presentFrame(at: timestamp)
        }
    }

    func flush() {
        scheduler.cancel()
        frameScheduled = false
        guard let value = pendingValue else { return }
        pendingValue = nil
        pendingPriority = nil
        present(value)
    }

    func cancel() {
        scheduler.cancel()
        frameScheduled = false
        pendingValue = nil
        pendingPriority = nil
    }

    private func presentFrame(at timestamp: CFTimeInterval) {
        frameScheduled = false
        guard let value = pendingValue else { return }
        pendingValue = nil
        lastPriority = pendingPriority
        pendingPriority = nil
        lastPresentationTime = timestamp
        present(value)
    }
}

@MainActor
final class DisplayLinkFrameScheduler: NSObject, DisplayFrameScheduling {
    private var displayLink: CADisplayLink?
    private var action: DisplayFrameAction?
    private var deadline: CFTimeInterval?

    func schedule(
        notBefore deadline: CFTimeInterval,
        _ action: @escaping DisplayFrameAction
    ) {
        self.action = action
        self.deadline = min(self.deadline ?? deadline, deadline)
        let link = displayLink ?? makeDisplayLink()
        guard let link else {
            self.action = nil
            self.deadline = nil
            action(CACurrentMediaTime())
            return
        }
        displayLink = link
        link.isPaused = false
    }

    func cancel() {
        action = nil
        deadline = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleFrame(_ link: CADisplayLink) {
        let timestamp = link.targetTimestamp
        guard timestamp >= (deadline ?? timestamp) else { return }
        link.isPaused = true
        let current = action
        action = nil
        deadline = nil
        current?(timestamp)
    }

    private func makeDisplayLink() -> CADisplayLink? {
        let target = NSApp.keyWindow ?? NSApp.mainWindow
        let link = target?.displayLink(
            target: self,
            selector: #selector(handleFrame(_:))
        ) ?? NSScreen.main?.displayLink(
            target: self,
            selector: #selector(handleFrame(_:))
        )
        link?.add(to: .main, forMode: .common)
        link?.isPaused = true
        return link
    }
}
