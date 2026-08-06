import CryptoKit
import Foundation

enum GameArchive {
    private static let maximumListingBytes = 32 * 1024 * 1024
    private static let maximumArchiveEntries = 200_000
    private static let maximumExtractedPaths = 1_000_000
    private static let maximumExtractedBytes: Int64 = 256 * 1024 * 1024 * 1024

    private struct ArchivePaths {
        var files: Set<String> = []
        var directories: Set<String> = []

        var count: Int { files.count + directories.count }

        mutating func insert(_ path: String, directory: Bool) throws {
            let components = path.split(separator: "/")
            var prefix: [Substring] = []
            for component in components.dropLast() {
                prefix.append(component)
                if files.contains(prefix.joined(separator: "/")) {
                    throw LauncherCoreError(code: "archive_extract_failed", message: "安装包文件结构冲突")
                }
            }
            if directory {
                guard !files.contains(path) else {
                    throw LauncherCoreError(code: "archive_extract_failed", message: "安装包文件结构冲突")
                }
                directories.insert(path)
            } else {
                guard !files.contains(path), !directories.contains(path) else {
                    throw LauncherCoreError(code: "archive_extract_failed", message: "安装包包含重复路径")
                }
                files.insert(path)
            }
        }

        mutating func formUnion(_ other: ArchivePaths) {
            files.formUnion(other.files)
            directories.formUnion(other.directories)
        }
    }

    static func install(
        segments: [PackageSegment],
        cache: URL,
        destination: URL,
        checkpoint: @escaping @Sendable () async throws -> Void
    ) async throws {
        try PrivateFilesystem.ensureDirectory(cache)
        try PrivateFilesystem.ensureDirectory(destination)
        try PrivateFilesystem.rejectSymbolicLinksRecursively(in: destination)
        let archives = try await downloadAll(
            segments: segments,
            cache: cache,
            checkpoint: checkpoint
        )
        let extractionRoot = cache.appending(path: ".extract-\(UUID().uuidString)")
        try PrivateFilesystem.ensureDirectory(extractionRoot)
        defer { try? PrivateFilesystem.removeDirectoryIfPresent(extractionRoot) }
        var extractedPaths = ArchivePaths()
        for archive in archives {
            try await checkpoint()
            let paths = try await extract(archive, to: extractionRoot, existingPaths: extractedPaths)
            extractedPaths.formUnion(paths)
            guard extractedPaths.count <= maximumExtractedPaths else {
                throw LauncherCoreError(code: "archive_too_large", message: "安装包文件数量超过限制")
            }
        }
        try PrivateFilesystem.rejectSymbolicLinksRecursively(in: extractionRoot)
        try merge(extractionRoot, into: destination)
    }

    private static func downloadAll(
        segments: [PackageSegment],
        cache: URL,
        checkpoint: @escaping @Sendable () async throws -> Void
    ) async throws -> [URL] {
        var archives: [URL] = []
        archives.reserveCapacity(segments.count)
        for segment in segments {
            try await checkpoint()
            archives.append(try await download(segment, cache: cache))
        }
        return archives
    }

    private static func download(_ segment: PackageSegment, cache: URL) async throws -> URL {
        guard HTTPSHostPolicy.sophon.allows(segment.url) else {
            throw LauncherCoreError(code: "sophon_segment_download_failed", message: "游戏安装包下载地址不受信任")
        }
        let destination = try GameFilesystem.safeTarget(root: cache, relativePath: segment.filename)
        if valid(destination, size: segment.size, md5: segment.md5) { return destination }
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        try removeFileIfPresent(destination)
        let partial = URL(filePath: destination.path + ".part")
        try PrivateFilesystem.rejectSymbolicLinks(in: partial)
        try removeFileIfPresent(partial)
        try GameFilesystem.ensureParent(of: partial)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3_600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let delegate = GameArchiveRedirectDelegate(policy: .sophon)
        let (bytes, response) = try await session.bytes(
            for: URLRequest(url: segment.url, timeoutInterval: 60),
            delegate: delegate
        )
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              (http.url.map { HTTPSHostPolicy.sophon.allows($0) } ?? false),
              http.expectedContentLength <= segment.size else {
            throw LauncherCoreError(code: "sophon_segment_download_failed", message: "游戏安装包下载失败")
        }
        guard FileManager.default.createFile(
            atPath: partial.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw LauncherCoreError(code: "sophon_storage_failed", message: "无法创建游戏安装包临时文件")
        }
        let handle = try FileHandle(forWritingTo: partial)
        var hasher = Insecure.MD5()
        var buffer = Data()
        var received: Int64 = 0
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                received += 1
                guard received <= segment.size else {
                    throw LauncherCoreError(code: "sophon_segment_too_large", message: "游戏安装包超过大小限制")
                }
                buffer.append(byte)
                if buffer.count >= 1024 * 1024 {
                    hasher.update(data: buffer)
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                hasher.update(data: buffer)
                try handle.write(contentsOf: buffer)
            }
            try handle.synchronize()
            try handle.close()
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard received == segment.size, digest == segment.md5.lowercased() else {
                throw LauncherCoreError(code: "sophon_segment_invalid", message: "游戏安装包校验失败")
            }
            try PrivateFilesystem.rejectSymbolicLinks(in: destination)
            try removeFileIfPresent(destination)
            try FileManager.default.moveItem(at: partial, to: destination)
            try PrivateFilesystem.setPrivateFilePermissions(destination)
            return destination
        } catch {
            try? handle.close()
            try? removeFileIfPresent(partial)
            throw error
        }
    }

    private static func valid(_ url: URL, size: Int64, md5 expected: String) -> Bool {
        guard GameFilesystem.regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              Int64(fileSize) == size else { return false }
        return (try? FileDigest.md5Sync(url)) == expected.lowercased()
    }

    private static func extract(
        _ archive: URL,
        to root: URL,
        existingPaths: ArchivePaths
    ) async throws -> ArchivePaths {
        guard GameFilesystem.regularFile(archive) else {
            throw LauncherCoreError(code: "sophon_segment_missing", message: "游戏安装包不存在")
        }
        let paths = try await runListing(arguments: ["-t", "-f", archive.path])
        let modes = try await runListing(arguments: ["-t", "-v", "-f", archive.path])
        let pathEntries = paths.split(whereSeparator: \.isNewline)
        let modeEntries = modes.split(whereSeparator: \.isNewline)
        guard pathEntries.count == modeEntries.count,
              pathEntries.count <= maximumArchiveEntries else {
            throw LauncherCoreError(code: "archive_too_large", message: "安装包文件数量超过限制")
        }
        var currentPaths = existingPaths
        var listedSize: Int64 = 0
        for (raw, modeRaw) in zip(pathEntries, modeEntries) {
            let line = String(modeRaw).trimmingCharacters(in: .whitespaces)
            guard let type = line.first, type == "-" || type == "d" else {
                throw LauncherCoreError(code: "archive_link_unsupported", message: "安装包包含链接或特殊文件")
            }
            var name = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            while name.hasSuffix("/") { name.removeLast() }
            while name.hasPrefix("./") { name.removeFirst(2) }
            if !name.isEmpty {
                guard !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw LauncherCoreError(code: "archive_traversal", message: "安装包包含不安全路径")
                }
                let normalized = name.replacingOccurrences(of: "\\", with: "/")
                let canonical = SophonValidation.canonicalPath(normalized)
                _ = try GameFilesystem.safeTarget(root: root, relativePath: normalized)
                try currentPaths.insert(canonical, directory: type == "d")
                guard currentPaths.count <= maximumExtractedPaths else {
                    throw LauncherCoreError(code: "archive_too_large", message: "安装包文件数量超过限制")
                }
            }
            let fields = line.split(maxSplits: 5, omittingEmptySubsequences: true)
            guard fields.count >= 5, let size = Int64(fields[4]), size >= 0,
                  size <= maximumExtractedBytes,
                  listedSize <= maximumExtractedBytes - size else {
                throw LauncherCoreError(code: "archive_too_large", message: "安装包解压后超过大小限制")
            }
            listedSize += size
        }

        try PrivateFilesystem.rejectSymbolicLinksRecursively(in: root)
        let status = try await run(arguments: ["-x", "-m", "-f", archive.path, "-C", root.path])
        guard status == 0 else {
            throw LauncherCoreError(code: "archive_extract_failed", message: "游戏安装包解压失败")
        }
        try PrivateFilesystem.rejectSymbolicLinksRecursively(in: root)
        guard directorySize(root) <= maximumExtractedBytes else {
            throw LauncherCoreError(code: "archive_too_large", message: "游戏安装包解压后超过大小限制")
        }
        return currentPaths
    }

    private static func merge(_ source: URL, into destination: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { throw LauncherCoreError(code: "archive_extract_failed", message: "无法读取游戏安装包内容") }
        let entries = enumerator.compactMap { $0 as? URL }.sorted {
            $0.pathComponents.count < $1.pathComponents.count
        }
        for entry in entries {
            guard let relative = relativePath(entry, under: source) else {
                throw LauncherCoreError(code: "archive_traversal", message: "安装包包含不安全路径")
            }
            let target = try GameFilesystem.safeTarget(root: destination, relativePath: relative)
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw LauncherCoreError(code: "archive_link_unsupported", message: "安装包包含符号链接")
            }
            if SophonValidation.isLauncherManagedPath(relative) {
                guard values.isRegularFile == true else {
                    throw LauncherCoreError(code: "archive_extract_failed", message: "安装包包含无效的启动器管理文件路径")
                }
                try PrivateFilesystem.removeRegularFileIfPresent(entry)
                continue
            }
            if values.isDirectory == true {
                if FileManager.default.fileExists(atPath: target.path) {
                    let targetValues = try? target.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                    )
                    guard targetValues?.isDirectory == true, targetValues?.isSymbolicLink != true else {
                        throw LauncherCoreError(code: "archive_extract_failed", message: "安装包目录结构冲突")
                    }
                } else {
                    try PrivateFilesystem.ensureDirectory(target)
                }
            } else if values.isRegularFile == true {
                try GameFilesystem.ensureParent(of: target)
                if FileManager.default.fileExists(atPath: target.path) {
                    guard GameFilesystem.regularFile(target) else {
                        throw LauncherCoreError(code: "archive_extract_failed", message: "安装包文件结构冲突")
                    }
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: entry)
                } else {
                    try FileManager.default.moveItem(at: entry, to: target)
                }
                try PrivateFilesystem.setPrivateFilePermissions(target)
            } else {
                throw LauncherCoreError(code: "archive_link_unsupported", message: "安装包包含特殊文件")
            }
        }
    }

    static func verifyManifest(in root: URL) throws {
        let manifest = root.appending(path: "mhg-manifest.json")
        guard GameFilesystem.regularFile(manifest) else { return }
        guard let values = try? manifest.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? Int.max) <= 4 * 1024 * 1024,
              let data = try? Data(contentsOf: manifest),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = object["files"] as? [String: String],
              files.count <= 100_000 else {
            throw LauncherCoreError(code: "installed_file_invalid", message: "游戏安装包校验清单无效")
        }
        var names = Set<String>()
        for (name, expected) in files {
            guard expected.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
                throw LauncherCoreError(code: "installed_file_invalid", message: "游戏安装包校验清单无效")
            }
            guard names.insert(SophonValidation.canonicalPath(name)).inserted else {
                throw LauncherCoreError(code: "installed_file_invalid", message: "游戏安装包校验清单包含重复路径")
            }
            let target = try GameFilesystem.safeTarget(root: root, relativePath: name)
            guard !SophonValidation.isLauncherManagedPath(name) else { continue }
            guard GameFilesystem.regularFile(target),
                  try FileDigest.sha256(target) == expected.lowercased() else {
                throw LauncherCoreError(code: "installed_file_invalid", message: "游戏安装包安装校验失败")
            }
        }
    }

    private static func relativePath(_ entry: URL, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let entryPath = entry.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard entryPath.hasPrefix(prefix) else { return nil }
        return String(entryPath.dropFirst(prefix.count))
    }

    private static func removeFileIfPresent(_ url: URL) throws {
        try PrivateFilesystem.rejectSymbolicLinks(in: url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard GameFilesystem.regularFile(url) else {
            throw LauncherCoreError(code: "archive_extract_failed", message: "安装包缓存路径不是普通文件")
        }
        try PrivateFilesystem.removeRegularFileIfPresent(url)
    }

    private static func directorySize(_ root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []
        ) else { return Int64.max }
        var total: Int64 = 0
        while let entry = enumerator.nextObject() as? URL {
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? -1)
            guard size >= 0, total <= Int64.max - size else { return Int64.max }
            total += size
        }
        return total
    }

    private static func runListing(arguments: [String]) async throws -> String {
        let capture = BoundedProcessCapture(limit: maximumListingBytes)
        do {
            let status = try await run(
                arguments: arguments,
                output: capture.pipe.fileHandleForWriting
            )
            capture.closeWriter()
            let data: Data
            do {
                data = try capture.finish()
            } catch {
                throw LauncherCoreError(code: "archive_too_large", message: "安装包目录输出超过限制")
            }
            guard status == 0, let value = String(data: data, encoding: .utf8) else {
                throw LauncherCoreError(code: "archive_extract_failed", message: "无法读取游戏安装包目录")
            }
            return value
        } catch {
            capture.closeWriter()
            _ = try? capture.finish()
            throw error
        }
    }

    private static func run(arguments: [String], output: FileHandle? = nil) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/bsdtar")
        process.arguments = arguments
        process.environment = CoreProcessEnvironment.sanitizedCurrentProcess()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try process.run()
            process.waitUntilExit()
            try Task.checkCancellation()
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        return process.terminationStatus
    }
}

private final class GameArchiveRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: HTTPSHostPolicy
    private var redirects = 0

    init(policy: HTTPSHostPolicy) { self.policy = policy }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard redirects < 3, let url = request.url, policy.allows(url) else {
            completionHandler(nil)
            return
        }
        redirects += 1
        completionHandler(request)
    }
}
