import CryptoKit
import Foundation
enum RuntimeInstallError: LocalizedError, Equatable {
    case invalidManifest
    case missingBundledBackend
    case downloadFailed(String)
    case checksumMismatch(String)
    case archiveTraversal(String)
    case processFailed(String)
    case unsafePromotion

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "运行时清单无效"
        case .missingBundledBackend: "应用内缺少后端资源"
        case let .downloadFailed(file): "无法下载 \(file)"
        case let .checksumMismatch(file): "\(file) 校验失败"
        case let .archiveTraversal(path): "运行时压缩包包含不安全路径：\(path)"
        case let .processFailed(command): "运行时命令执行失败：\(command)"
        case .unsafePromotion: "运行时提升记录不安全，已拒绝删除文件"
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
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
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
        try? FileManager.default.removeItem(at: partial)
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let writer = try FileHandle(forWritingTo: partial)
        defer { try? writer.close() }
        for part in parts {
            try Task.checkCancellation()
            let partURL = try await download(named: part.file, manifest: manifest, cacheURL: cacheURL, size: part.size, sha256: part.sha256, sources: sources)
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
        sha256 expected: String,
        sources: [RuntimeDownloadSource]
    ) async throws -> URL {
        let destination = cacheURL.appending(path: file)
        if isValid(destination, size: size, sha256: expected) { return destination }
        let candidates = sources.isEmpty
            ? [RuntimeDownloadSource(id: "manifest", baseURL: manifest.assetBaseURL)]
            : sources
        var checksumFailed = false
        for candidate in candidates {
            try Task.checkCancellation()
            let partial = destination.appendingPathExtension("part")
            try? FileManager.default.removeItem(at: partial)
            let source = candidate.assetURL(named: file)
            do {
                if source.isFileURL {
                    let localSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
                    guard Int64(localSize) == size else {
                        checksumFailed = true
                        continue
                    }
                    try FileManager.default.copyItem(at: source, to: partial)
                } else {
                    try await RuntimeArchiveRemote.download(from: source, to: partial, limit: size)
                }
                guard isValid(partial, size: size, sha256: expected) else {
                    checksumFailed = true
                    continue
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: partial, to: destination)
                return destination
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: partial)
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                try? FileManager.default.removeItem(at: partial)
                throw error
            } catch {
                try? FileManager.default.removeItem(at: partial)
            }
        }
        try? FileManager.default.removeItem(at: destination.appendingPathExtension("part"))
        throw checksumFailed ? RuntimeInstallError.checksumMismatch(file) : RuntimeInstallError.downloadFailed(file)
    }

    private static func isValid(_ url: URL, size: Int64, sha256 expected: String) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              Int64(values.fileSize ?? -1) == size else { return false }
        return (try? sha256(url)) == expected.lowercased()
    }

}
