import Darwin
import Foundation

struct UnixSocketTransport: Sendable {
    let path: String

    func send(_ request: APIRequest) async throws -> APIResponse {
        try await Task.detached {
            let descriptor = try connect(path: path, timeout: request.timeout)
            defer { Darwin.close(descriptor) }
            try write(requestData(request), to: descriptor)
            return try parse(readAll(from: descriptor))
        }.value
    }

    static func parseResponse(_ data: Data) throws -> APIResponse {
        try parse(data)
    }
}

private func connect(path: String, timeout: TimeInterval) throws -> Int32 {
    guard path.utf8.count < MemoryLayout<sockaddr_un>.size - 2 else {
        throw POSIXError(.ENAMETOOLONG)
    }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    var value = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout.size(ofValue: value)))
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout.size(ofValue: value)))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: path.utf8)
        buffer[path.utf8.count] = 0
    }
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        let error = POSIXError(.init(rawValue: errno) ?? .EIO)
        Darwin.close(descriptor)
        throw error
    }
    return descriptor
}

private func requestData(_ request: APIRequest) -> Data {
    var headers = request.headers
    headers["Host"] = "localhost"
    headers["Connection"] = "close"
    headers["Content-Length"] = String(request.body?.count ?? 0)
    let fields = headers.sorted { $0.key < $1.key }
        .map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
    var data = Data("\(request.method) \(request.path) HTTP/1.1\r\n\(fields)\r\n\r\n".utf8)
    if let body = request.body { data.append(body) }
    return data
}

private func write(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        var offset = 0
        while offset < raw.count {
            let count = Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
            guard count > 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            offset += count
        }
    }
}

private func readAll(from descriptor: Int32) throws -> Data {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        if count == 0 { return result }
        guard count > 0 else {
            if errno == EINTR { continue }
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        result.append(buffer, count: count)
    }
}

private func parse(_ data: Data) throws -> APIResponse {
    let separator = Data("\r\n\r\n".utf8)
    guard let boundary = data.range(of: separator),
          let text = String(data: data[..<boundary.lowerBound], encoding: .utf8)
    else { throw URLError(.cannotParseResponse) }
    let lines = text.components(separatedBy: "\r\n")
    guard let status = lines.first?.split(separator: " ").dropFirst().first.flatMap({ Int($0) })
    else { throw URLError(.cannotParseResponse) }
    let pairs: [(String, String)] = lines.dropFirst().compactMap { line in
        guard let index = line.firstIndex(of: ":") else { return nil }
        return (line[..<index].lowercased(), line[line.index(after: index)...].trimmingCharacters(in: .whitespaces))
    }
    let headers = Dictionary(uniqueKeysWithValues: pairs)
    let body = Data(data[boundary.upperBound...])
    if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
        return APIResponse(status: status, body: try decodeChunks(body))
    }
    if let length = headers["content-length"].flatMap(Int.init), body.count < length {
        throw URLError(.networkConnectionLost)
    }
    return APIResponse(status: status, body: body)
}

private func decodeChunks(_ data: Data) throws -> Data {
    var cursor = data.startIndex
    var result = Data()
    let newline = Data("\r\n".utf8)
    while let range = data[cursor...].range(of: newline) {
        guard let text = String(data: data[cursor..<range.lowerBound], encoding: .ascii),
              let size = Int(text.split(separator: ";", maxSplits: 1)[0], radix: 16)
        else { throw URLError(.cannotParseResponse) }
        cursor = range.upperBound
        if size == 0 { return result }
        guard data.distance(from: cursor, to: data.endIndex) >= size + 2 else {
            throw URLError(.networkConnectionLost)
        }
        result.append(data[cursor..<data.index(cursor, offsetBy: size)])
        cursor = data.index(cursor, offsetBy: size + 2)
    }
    throw URLError(.cannotParseResponse)
}
