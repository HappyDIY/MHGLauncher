import Foundation

extension RuntimeArchive {
    private static let maximumListingBytes = 32 * 1024 * 1024
    private static let maximumExtractedBytes: Int64 = 128 * 1024 * 1024 * 1024

    static func validateTarGzip(_ archiveURL: URL) async throws {
        guard GameFilesystem.regularFile(archiveURL) else {
            throw RuntimeInstallError.downloadFailed(archiveURL.lastPathComponent)
        }
        let output = try await runTarListing(arguments: ["-tzf", archiveURL.path])
        let entries = Array(output).split(separator: 0x0A).map { Data($0) }
        var seen = Set<String>()
        for entry in entries {
            guard let path = try validateTarPath(entry) else { continue }
            guard seen.insert(path).inserted else {
                throw RuntimeInstallError.archiveTraversal("压缩包包含重复路径")
            }
        }
        let modes = try await runTarListing(arguments: ["-tvzf", archiveURL.path])
        try validateTarEntryTypes(modes, entries: entries)
        try validateTarSize(modes)
    }

    static func extractTarGzip(_ archiveURL: URL, to destinationURL: URL) async throws {
        try await validateTarGzip(archiveURL)
        try PrivateFilesystem.ensureDirectory(destinationURL)
        try await runTar(arguments: ["-xzf", archiveURL.path, "-C", destinationURL.path])
    }

    private static func validateTarPath(_ data: Data) throws -> String? {
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw RuntimeInstallError.archiveTraversal("无效 UTF-8 路径")
        }
        var path = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") { path.removeFirst(2) }
        guard !path.hasPrefix("/"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw RuntimeInstallError.archiveTraversal(path)
        }
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains(".") else {
            throw RuntimeInstallError.archiveTraversal(path)
        }
        for (index, component) in components.enumerated() {
            guard !component.isEmpty || index == components.count - 1 else {
                throw RuntimeInstallError.archiveTraversal(path)
            }
        }
        let canonical = RuntimeManifest.canonicalPath(path)
        guard !canonical.hasPrefix("game-runtime/wine/bin/wineboot/") else {
            throw RuntimeInstallError.archiveTraversal(path)
        }
        return canonical
    }

    static func validateTarEntryTypes(_ data: Data, entries: [Data]) throws {
        let lines = Array(data).split(separator: 0x0A).map { Data($0) }
        guard lines.count == entries.count else {
            throw RuntimeInstallError.archiveTraversal("压缩包目录不一致")
        }
        for (line, entry) in zip(lines, entries) {
            if line.first == 0x2D || line.first == 0x64 { continue }
            if line.first == 0x6C {
                try validateSymlink(line: line, entry: entry)
            } else {
                throw RuntimeInstallError.archiveTraversal("链接或特殊文件")
            }
        }
    }

    private static func validateSymlink(line: Data, entry: Data) throws {
        guard let listing = String(data: line, encoding: .utf8),
              let rawPath = String(data: entry, encoding: .utf8) else {
            throw RuntimeInstallError.archiveTraversal("无效 UTF-8 链接")
        }
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("./") { path.removeFirst(2) }
        let markers = ["\(rawPath) -> ", "\(path) -> "]
        guard let range = markers.lazy.compactMap({ listing.range(of: $0, options: .backwards) }).first else {
            throw RuntimeInstallError.archiveTraversal("无效符号链接")
        }
        let target = String(listing[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard path == "game-runtime/wine/bin/wineboot", target == "wine" else {
            throw RuntimeInstallError.archiveTraversal(path)
        }
    }

    private static func validateTarSize(_ data: Data) throws {
        var total: Int64 = 0
        for raw in Array(data).split(separator: 0x0A) {
            let line = String(decoding: raw, as: UTF8.self)
            let fields = line.split(maxSplits: 5, omittingEmptySubsequences: true)
            guard fields.count >= 5, let size = Int64(fields[4]), size >= 0,
                  size <= maximumExtractedBytes,
                  total <= maximumExtractedBytes - size else {
                throw RuntimeInstallError.archiveTraversal("压缩包解压后超过大小限制")
            }
            total += size
        }
    }

    private static func runTarListing(arguments: [String]) async throws -> Data {
        let capture = BoundedProcessCapture(limit: maximumListingBytes)
        do {
            try await runTar(arguments: arguments, output: capture.pipe.fileHandleForWriting)
            capture.closeWriter()
            do {
                return try capture.finish()
            } catch {
                throw RuntimeInstallError.archiveTraversal("压缩包目录超过大小限制")
            }
        } catch {
            capture.closeWriter()
            _ = try? capture.finish()
            throw error
        }
    }

    private static func runTar(arguments: [String], output: FileHandle? = nil) async throws {
        let process = Process()
        let error = Pipe()
        let errorDrain = ProcessPipeDrain(
            handle: error.fileHandleForReading
        )
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        process.environment = CoreProcessEnvironment.sanitizedCurrentProcess()
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = error
        defer { errorDrain.close() }
        try Task.checkCancellation()
        try process.run()
        try await withTaskCancellationHandler {
            process.waitUntilExit()
            try Task.checkCancellation()
        } onCancel: {
            process.terminate()
        }
        guard process.terminationStatus == 0 else {
            throw RuntimeInstallError.processFailed(arguments.joined(separator: " "))
        }
        if let index = arguments.firstIndex(of: "-C"), index + 1 < arguments.count {
            try RuntimeInstallLedger.validateTree(at: URL(filePath: arguments[index + 1]))
        }
    }
}
