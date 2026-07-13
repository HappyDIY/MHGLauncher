import Foundation

enum RuntimeArchiveRemote {
    static func download(from source: URL, to destination: URL, limit: Int64) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3_600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: source)
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode,
              response.expectedContentLength <= limit else {
            throw URLError(.badServerResponse)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        var received: Int64 = 0
        for try await byte in bytes {
            received += 1
            guard received <= limit else { throw URLError(.dataLengthExceedsMaximum) }
            buffer.append(byte)
            if buffer.count >= 1024 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
        try handle.synchronize()
    }
}
