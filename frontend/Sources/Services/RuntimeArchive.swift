import CryptoKit
import Foundation

enum RuntimeInstallError: LocalizedError, Equatable {
    case invalidManifest
    case missingBundledBackend
    case checksumMismatch(String)
    case archiveTraversal(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "运行时清单无效"
        case .missingBundledBackend: "应用内缺少后端资源"
        case let .checksumMismatch(file): "\(file) 校验失败"
        case let .archiveTraversal(path): "运行时压缩包包含不安全路径：\(path)"
        case let .processFailed(command): "运行时命令执行失败：\(command)"
        }
    }
}

enum RuntimeArchive {
    static func materialize(
        component: RuntimeComponent,
        manifest: RuntimeManifest,
        cacheURL: URL
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        let archiveURL = cacheURL.appending(path: component.file)
        if isValid(archiveURL, size: component.size, sha256: component.sha256) {
            return archiveURL
        }
        if let parts = component.parts, !parts.isEmpty {
            try await combine(parts: parts, manifest: manifest, cacheURL: cacheURL, output: archiveURL)
        } else {
            try await download(
                named: component.file,
                manifest: manifest,
                cacheURL: cacheURL,
                size: component.size,
                sha256: component.sha256
            )
        }
        guard isValid(archiveURL, size: component.size, sha256: component.sha256) else {
            throw RuntimeInstallError.checksumMismatch(component.file)
        }
        return archiveURL
    }

    static func validateTarGzip(_ archiveURL: URL) throws {
        let output = try runTarListing(arguments: ["-tzf", archiveURL.path])
        var current = Data()
        for byte in output {
            if byte == 0x0A {
                try validateTarPath(current)
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        if !current.isEmpty { try validateTarPath(current) }
    }

    static func extractTarGzip(_ archiveURL: URL, to destinationURL: URL) throws {
        try validateTarGzip(archiveURL)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try runTar(arguments: ["-xzf", archiveURL.path, "-C", destinationURL.path])
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func combine(
        parts: [RuntimeAssetPart],
        manifest: RuntimeManifest,
        cacheURL: URL,
        output: URL
    ) async throws {
        let partial = output.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partial)
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let writer = try FileHandle(forWritingTo: partial)
        defer { try? writer.close() }
        for part in parts {
            let partURL = try await download(
                named: part.file,
                manifest: manifest,
                cacheURL: cacheURL,
                size: part.size,
                sha256: part.sha256
            )
            let reader = try FileHandle(forReadingFrom: partURL)
            defer { try? reader.close() }
            while true {
                let data = reader.readData(ofLength: 1024 * 1024)
                if data.isEmpty { break }
                writer.write(data)
            }
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: partial, to: output)
    }

    @discardableResult
    private static func download(
        named file: String,
        manifest: RuntimeManifest,
        cacheURL: URL,
        size: Int64,
        sha256 expected: String
    ) async throws -> URL {
        let destination = cacheURL.appending(path: file)
        if isValid(destination, size: size, sha256: expected) { return destination }
        let partial = destination.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partial)
        let source = manifest.assetBaseURL.appending(path: file)
        if source.isFileURL {
            try FileManager.default.copyItem(at: source, to: partial)
        } else {
            let (temporary, _) = try await URLSession.shared.download(from: source)
            try FileManager.default.moveItem(at: temporary, to: partial)
        }
        guard isValid(partial, size: size, sha256: expected) else {
            throw RuntimeInstallError.checksumMismatch(file)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    private static func isValid(_ url: URL, size: Int64, sha256 expected: String) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? -1) == size else { return false }
        return (try? sha256(url)) == expected.lowercased()
    }

    private static func validateTarPath(_ data: Data) throws {
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if path.hasPrefix("/") || path == ".." || path.contains("../") {
            throw RuntimeInstallError.archiveTraversal(path)
        }
    }

    private static func runTarListing(arguments: [String]) throws -> Data {
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "mhg-tar-list-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        try runTar(arguments: arguments, output: output)
        return try Data(contentsOf: temporary)
    }

    private static func runTar(arguments: [String], output: FileHandle? = nil) throws {
        let process = Process()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = error
        try process.run()
        error.fileHandleForReading.readabilityHandler = { _ in }
        process.waitUntilExit()
        error.fileHandleForReading.readabilityHandler = nil
        guard process.terminationStatus == 0 else {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? arguments.joined(separator: " ")
            throw RuntimeInstallError.processFailed(message)
        }
    }
}
