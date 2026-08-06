import Foundation

final class ProcessPipeDrain: @unchecked Sendable {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { source in _ = source.availableData }
    }

    func close() {
        handle.readabilityHandler = nil
        try? handle.close()
    }
}

final class BoundedProcessCapture: @unchecked Sendable {
    let pipe = Pipe()

    private let limit: Int
    private let readHandle: FileHandle
    private let readLock = NSLock()
    private let stateLock = NSLock()
    private let finishLock = NSLock()
    private var data = Data()
    private var exceeded = false
    private var finished = false

    init(limit: Int) {
        self.limit = max(1, limit)
        readHandle = pipe.fileHandleForReading
        readHandle.readabilityHandler = { [weak self] handle in
            self?.consumeAvailable(from: handle)
        }
    }

    func closeWriter() {
        try? pipe.fileHandleForWriting.close()
    }

    func finish() throws -> Data {
        finishLock.lock()
        defer { finishLock.unlock() }
        stateLock.lock()
        if finished {
            let value = data
            let didExceed = exceeded
            stateLock.unlock()
            guard !didExceed else { throw CocoaError(.fileReadTooLarge) }
            return value
        }
        stateLock.unlock()
        readHandle.readabilityHandler = nil
        while true {
            let chunk = readAvailable(from: readHandle)
            if chunk.isEmpty { break }
            consume(chunk)
        }
        try? readHandle.close()

        stateLock.lock()
        finished = true
        let value = data
        let didExceed = exceeded
        stateLock.unlock()
        guard !didExceed else { throw CocoaError(.fileReadTooLarge) }
        return value
    }

    private func consumeAvailable(from handle: FileHandle) {
        let chunk = readAvailable(from: handle)
        if !chunk.isEmpty { consume(chunk) }
    }

    private func readAvailable(from handle: FileHandle) -> Data {
        readLock.lock()
        defer { readLock.unlock() }
        return handle.availableData
    }

    private func consume(_ chunk: Data) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !finished else { return }
        let remaining = limit - data.count
        if remaining > 0 {
            let amount = min(remaining, chunk.count)
            data.append(contentsOf: chunk.prefix(amount))
            exceeded = exceeded || amount < chunk.count
        } else {
            exceeded = true
        }
    }
}
