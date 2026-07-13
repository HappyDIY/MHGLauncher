import Foundation

enum UIGFFileIO {
    static let maximumImportBytes = 64 * 1024 * 1024

    static func read(from url: URL) throws -> Data {
        try withSecurityScope(url) {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? maximumImportBytes + 1
            guard size <= maximumImportBytes else { throw URLError(.dataLengthExceedsMaximum) }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var result = Data()
            while true {
                let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
                if chunk.isEmpty { return result }
                guard result.count <= maximumImportBytes - chunk.count else {
                    throw URLError(.dataLengthExceedsMaximum)
                }
                result.append(chunk)
            }
        }
    }

    static func write(_ data: Data, to url: URL) throws {
        let formatted = try formattedJSON(data)
        try withSecurityScope(url) {
            try formatted.write(to: url, options: .atomic)
        }
    }

    static func formattedJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func withSecurityScope<T>(
        _ url: URL,
        operation: () throws -> T
    ) rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}
