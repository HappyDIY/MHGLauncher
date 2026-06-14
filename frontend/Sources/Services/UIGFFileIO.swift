import Foundation

enum UIGFFileIO {
    static func read(from url: URL) throws -> Data {
        try withSecurityScope(url) {
            try Data(contentsOf: url)
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
