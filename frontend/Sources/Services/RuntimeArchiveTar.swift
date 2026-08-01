import Foundation

extension RuntimeArchive {
    static func validateTarGzip(_ archiveURL: URL) async throws {
        let output = try await runTarListing(arguments: ["-tzf", archiveURL.path])
        let entries = Array(output).split(separator: 0x0A).map { Data($0) }
        for entry in entries { try validateTarPath(entry) }
        try validateTarEntryTypes(
            try await runTarListing(arguments: ["-tvzf", archiveURL.path]),
            entries: entries
        )
    }

    static func extractTarGzip(_ archiveURL: URL, to destinationURL: URL) async throws {
        try await validateTarGzip(archiveURL)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try await runTar(arguments: ["-xzf", archiveURL.path, "-C", destinationURL.path])
    }

    private static func validateTarPath(_ data: Data) throws {
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw RuntimeInstallError.archiveTraversal("无效 UTF-8 路径")
        }
        let path = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.hasPrefix("/"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw RuntimeInstallError.archiveTraversal(path)
        }
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
              let path = String(data: entry, encoding: .utf8) else {
            throw RuntimeInstallError.archiveTraversal("无效 UTF-8 链接")
        }
        let marker = "\(path) -> "
        guard let range = listing.range(of: marker, options: .backwards) else {
            throw RuntimeInstallError.archiveTraversal("无效符号链接")
        }
        let target = String(listing[range.upperBound...])
        guard symlinkTargetIsContained(target, entry: path) else {
            throw RuntimeInstallError.archiveTraversal(path)
        }
    }

    private static func symlinkTargetIsContained(_ target: String, entry: String) -> Bool {
        guard !target.isEmpty, !target.hasPrefix("/") else { return false }
        var components = entry.split(separator: "/").dropLast().filter { $0 != "." }
        for part in target.split(separator: "/", omittingEmptySubsequences: false) {
            if part == ".." {
                guard !components.isEmpty else { return false }
                components.removeLast()
            } else if part != "." && !part.isEmpty {
                components.append(part)
            }
        }
        return true
    }

    private static func runTarListing(arguments: [String]) async throws -> Data {
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: "mhg-tar-list-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        try await runTar(arguments: arguments, output: output)
        return try Data(contentsOf: temporary)
    }

    private static func runTar(arguments: [String], output: FileHandle? = nil) async throws {
        let process = Process()
        let error = Pipe()
        let errorDrain = ProcessPipeDrain(
            handle: error.fileHandleForReading,
            capturesReady: false
        )
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
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
    }
}
