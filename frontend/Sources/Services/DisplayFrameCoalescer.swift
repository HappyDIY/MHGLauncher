import AppKit
import QuartzCore

typealias DisplayFrameAction = @MainActor () -> Void

@MainActor
protocol DisplayFrameScheduling: AnyObject {
    func schedule(_ action: @escaping DisplayFrameAction)
    func cancel()
}

@MainActor
final class LatestDisplayFrameCoalescer<Value> {
    private let scheduler: any DisplayFrameScheduling
    private let present: (Value) -> Void
    private var pendingValue: Value?
    private var frameScheduled = false

    init(
        scheduler: any DisplayFrameScheduling,
        present: @escaping (Value) -> Void
    ) {
        self.scheduler = scheduler
        self.present = present
    }

    func submit(_ value: Value) {
        pendingValue = value
        guard !frameScheduled else { return }
        frameScheduled = true
        scheduler.schedule { [weak self] in
            self?.presentFrame()
        }
    }

    func flush() {
        scheduler.cancel()
        frameScheduled = false
        guard let value = pendingValue else { return }
        pendingValue = nil
        present(value)
    }

    func cancel() {
        scheduler.cancel()
        frameScheduled = false
        pendingValue = nil
    }

    private func presentFrame() {
        frameScheduled = false
        guard let value = pendingValue else { return }
        pendingValue = nil
        present(value)
    }
}

@MainActor
final class DisplayLinkFrameScheduler: NSObject, DisplayFrameScheduling {
    private var displayLink: CADisplayLink?
    private var action: DisplayFrameAction?

    func schedule(_ action: @escaping DisplayFrameAction) {
        self.action = action
        let link = displayLink ?? makeDisplayLink()
        guard let link else {
            self.action = nil
            action()
            return
        }
        displayLink = link
        link.isPaused = false
    }

    func cancel() {
        action = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleFrame(_ link: CADisplayLink) {
        link.isPaused = true
        let current = action
        action = nil
        current?()
    }

    private func makeDisplayLink() -> CADisplayLink? {
        let application = NSApplication.shared
        let target = application.keyWindow ?? application.mainWindow
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
