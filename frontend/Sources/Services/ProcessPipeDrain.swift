import Foundation

final class ProcessPipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let capturesReady: Bool
    private let lock = NSLock()
    private var buffer = Data()
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private var readyResult: Result<String, Error>?

    init(handle: FileHandle, capturesReady: Bool) {
        self.handle = handle
        self.capturesReady = capturesReady
        handle.readabilityHandler = { [weak self] source in self?.consume(source.availableData) }
    }

    func readyPath(timeout: Duration = .seconds(15)) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result = readyResult { lock.unlock(); continuation.resume(with: result); return }
                self.continuation = continuation
                lock.unlock()
                Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.fail(URLError(.timedOut))
                }
            }
        } onCancel: { self.fail(CancellationError()) }
    }

    func close() {
        handle.readabilityHandler = nil
        try? handle.close()
        fail(CancellationError())
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { fail(CocoaError(.fileReadCorruptFile)); return }
        guard capturesReady else { return }
        lock.lock()
        guard !finished else { lock.unlock(); return }
        buffer.append(data)
        guard buffer.count <= 16_384, let newline = buffer.firstIndex(of: 0x0A) else {
            let oversized = buffer.count > 16_384
            lock.unlock()
            if oversized { fail(CocoaError(.fileReadTooLarge)) }
            return
        }
        let line = Data(buffer[..<newline])
        do {
            let object = try JSONSerialization.jsonObject(with: line)
            guard let payload = object as? [String: Any], payload["event"] as? String == "ready",
                  let path = payload["socket_path"] as? String else { throw CocoaError(.fileReadCorruptFile) }
            let continuation = finishLocked(.success(path)); lock.unlock(); continuation?.resume(returning: path)
        } catch {
            lock.unlock(); fail(error)
        }
    }

    private func fail(_ error: Error) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let continuation = finishLocked(.failure(error)); lock.unlock(); continuation?.resume(throwing: error)
    }

    private func finishLocked(_ result: Result<String, Error>) -> CheckedContinuation<String, Error>? {
        finished = true; readyResult = result; buffer.removeAll(keepingCapacity: false)
        let value = continuation; continuation = nil; return value
    }
}
