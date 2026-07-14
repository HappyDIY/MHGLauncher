import Foundation

actor AsyncSerialGate {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard locked else {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard let waiter = waiters.popLast() else {
            locked = false
            return
        }
        waiter.resume()
    }
}
