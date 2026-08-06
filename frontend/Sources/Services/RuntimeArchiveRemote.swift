import Foundation

enum RuntimeArchiveRemote {
    static func download(from source: URL, to destination: URL, limit: Int64) async throws {
        guard limit > 0,
              let host = source.host?.lowercased(),
              RuntimeURLPolicy.allowsRemote(source, additionalHosts: [host]) else {
            throw URLError(.unsupportedURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3_600
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delegate = RuntimeHTTPRedirectDelegate(additionalHosts: [host])
        let (bytes, response) = try await session.bytes(
            for: URLRequest(url: source, timeoutInterval: 30), delegate: delegate
        )
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode,
              RuntimeURLPolicy.allowsRemote(response.url ?? source, additionalHosts: [host]),
              response.expectedContentLength <= limit else {
            throw URLError(.badServerResponse)
        }
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        guard FileManager.default.createFile(
            atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
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
