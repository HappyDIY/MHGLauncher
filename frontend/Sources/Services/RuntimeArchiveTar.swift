import Foundation

extension RuntimeArchive {
    static func validateTarGzip(_ archiveURL: URL) async throws {
        let output = try await runTarListing(arguments: ["-tzf", archiveURL.path])
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

    static func extractTarGzip(_ archiveURL: URL, to destinationURL: URL) async throws {
        try await validateTarGzip(archiveURL)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try await runTar(arguments: ["-xzf", archiveURL.path, "-C", destinationURL.path])
    }

    private static func validateTarPath(_ data: Data) throws {
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if path.hasPrefix("/") || path == ".." || path.contains("../") {
            throw RuntimeInstallError.archiveTraversal(path)
        }
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
