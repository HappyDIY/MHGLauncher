import CryptoKit
import Foundation
enum RuntimeInstallError: LocalizedError, Equatable {
    case invalidManifest
    case missingRuntimeTool
    case downloadFailed(String)
    case checksumMismatch(String)
    case archiveTraversal(String)
    case processFailed(String)
    case unsafePromotion
    case incompatibleCoreRuntime

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "运行时清单无效"
        case .missingRuntimeTool: "缺少运行时工具"
        case let .downloadFailed(file): "无法下载 \(file)"
        case let .checksumMismatch(file): "\(file) 校验失败"
        case let .archiveTraversal(path): "运行时压缩包包含不安全路径：\(path)"
        case let .processFailed(command): "运行时命令执行失败：\(command)"
        case .unsafePromotion: "运行时提升记录不安全，已拒绝删除文件"
        case .incompatibleCoreRuntime: "下载的核心运行时与当前应用不兼容，请更新应用后重试"
        }
    }
}

enum RuntimeArchive {
    static func materialize(
        component: RuntimeComponent,
        manifest: RuntimeManifest,
        cacheURL: URL,
        sources: [RuntimeDownloadSource] = []
    ) async throws -> URL {
        try Task.checkCancellation()
        try PrivateFilesystem.ensureDirectory(cacheURL)
        let archiveURL = cacheURL.appending(path: component.file)
        if isValid(archiveURL, size: component.size, sha256: component.sha256) {
            return archiveURL
        }
        if let parts = component.parts, !parts.isEmpty {
            try await combine(parts: parts, manifest: manifest, cacheURL: cacheURL, output: archiveURL, sources: sources)
        } else {
            try await download(named: component.file, manifest: manifest, cacheURL: cacheURL, size: component.size, sha256: component.sha256, sources: sources)
        }
        guard isValid(archiveURL, size: component.size, sha256: component.sha256) else {
            throw RuntimeInstallError.checksumMismatch(component.file)
        }
        return archiveURL
    }

    static func sha256(_ url: URL) throws -> String {
        guard GameFilesystem.regularFile(url) else {
            throw RuntimeInstallError.downloadFailed(url.lastPathComponent)
        }
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
        output: URL,
        sources: [RuntimeDownloadSource]
    ) async throws {
        let partial = output.appendingPathExtension("part")
        try PrivateFilesystem.rejectSymbolicLinks(in: partial)
        try removeFileIfPresent(partial)
        guard FileManager.default.createFile(
            atPath: partial.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ) else { throw CocoaError(.fileWriteUnknown) }
        let writer = try FileHandle(forWritingTo: partial)
        defer {
            try? writer.close()
            try? removeFileIfPresent(partial)
        }
        for part in parts {
            try Task.checkCancellation()
            let partURL = try await download(named: part.file, manifest: manifest, cacheURL: cacheURL, size: part.size, sha256: part.sha256, sources: sources)
            let reader = try FileHandle(forReadingFrom: partURL)
            do {
                while true {
                    let data = reader.readData(ofLength: 1024 * 1024)
                    if data.isEmpty { break }
                    try writer.write(contentsOf: data)
                }
                try reader.close()
            } catch {
                try? reader.close()
                throw error
            }
        }
        try writer.synchronize()
        try writer.close()
        try PrivateFilesystem.rejectSymbolicLinks(in: output)
        try removeFileIfPresent(output)
        try FileManager.default.moveItem(at: partial, to: output)
    }

    @discardableResult
    private static func download(
        named file: String,
        manifest: RuntimeManifest,
        cacheURL: URL,
        size: Int64,
        sha256 expected: String,
        sources: [RuntimeDownloadSource]
    ) async throws -> URL {
        let destination = cacheURL.appending(path: file)
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        if isValid(destination, size: size, sha256: expected) { return destination }
        let official = RuntimeDownloadSource(id: "manifest", baseURL: manifest.assetBaseURL)
        let candidates = sources.isEmpty ? [official] : sources + [official]
        var checksumFailed = false
        for candidate in candidates {
            try Task.checkCancellation()
            let partial = destination.appendingPathExtension("part")
            try PrivateFilesystem.rejectSymbolicLinks(in: partial)
            try removeFileIfPresent(partial)
            let source = candidate.assetURL(named: file)
            do {
                if source.isFileURL {
                    guard GameFilesystem.regularFile(source) else {
                        throw RuntimeInstallError.downloadFailed(file)
                    }
                    let localSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
                    guard Int64(localSize) == size else {
                        checksumFailed = true
                        continue
                    }
                    try FileManager.default.copyItem(at: source, to: partial)
                    try PrivateFilesystem.setPrivateFilePermissions(partial)
                } else {
                    try await RuntimeArchiveRemote.download(from: source, to: partial, limit: size)
                }
                guard isValid(partial, size: size, sha256: expected) else {
                    checksumFailed = true
                    continue
                }
                try removeFileIfPresent(destination)
                try FileManager.default.moveItem(at: partial, to: destination)
                return destination
            } catch is CancellationError {
                bestEffortRemoveFile(partial)
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                bestEffortRemoveFile(partial)
                throw error
            } catch {
                bestEffortRemoveFile(partial)
            }
        }
        bestEffortRemoveFile(destination.appendingPathExtension("part"))
        throw checksumFailed ? RuntimeInstallError.checksumMismatch(file) : RuntimeInstallError.downloadFailed(file)
    }

    private static func isValid(_ url: URL, size: Int64, sha256 expected: String) -> Bool {
        guard GameFilesystem.regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? -1) == size else { return false }
        return (try? sha256(url)) == expected.lowercased()
    }

    private static func removeFileIfPresent(_ url: URL) throws {
        try PrivateFilesystem.rejectSymbolicLinks(in: url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard GameFilesystem.regularFile(url) else {
            throw RuntimeInstallError.unsafePromotion
        }
        try PrivateFilesystem.removeRegularFileIfPresent(url)
    }

    private static func bestEffortRemoveFile(_ url: URL) {
        try? removeFileIfPresent(url)
    }

}
