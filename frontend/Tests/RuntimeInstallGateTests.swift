import Foundation
import Testing
@testable import MHGLauncher

@Suite("运行时安装并发保护")
struct RuntimeInstallGateTests {
    @Test("取消等待者不会中断共享安装")
    func cancellingWaiterPreservesSharedFlight() async throws {
        let gate = RuntimeInstallGate()
        let signal = GateSignal()
        let first = Task {
            try await gate.run(scope: .core) {
                await signal.started()
                try await Task.sleep(for: .milliseconds(100))
                return runtime
            }
        }
        await signal.waitForStart()
        let second = Task { try await gate.run(scope: .core) { throw CancellationError() } }
        try await Task.sleep(for: .milliseconds(20))
        second.cancel()

        #expect(try await first.value == runtime)
        await #expect(throws: CancellationError.self) { _ = try await second.value }
    }
}

private actor GateSignal {
    private var didStart = false
    private var waiter: CheckedContinuation<Void, Never>?

    func started() {
        didStart = true
        waiter?.resume()
        waiter = nil
    }

    func waitForStart() async {
        guard !didStart else { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private let runtime = InstalledRuntime(
    tag: "test", rootURL: URL(fileURLWithPath: "/tmp/runtime"),
    backendAppURL: URL(fileURLWithPath: "/tmp/runtime/backend"),
    nodeURL: URL(fileURLWithPath: "/tmp/runtime/node"),
    hpatchzURL: URL(fileURLWithPath: "/tmp/runtime/hpatchz"),
    gameRuntimeURL: URL(fileURLWithPath: "/tmp/runtime/game")
)
