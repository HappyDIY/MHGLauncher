import CryptoKit
import Foundation

enum GameFilesystem {
    private static let maximumVersionFileBytes = 1024 * 1024

    static func validatedPath(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = URL(filePath: value).standardizedFileURL.path
        guard !value.isEmpty,
              value.utf8.count <= 4_096,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              path.hasPrefix("/"),
              path != "/" else {
            throw LauncherCoreError(code: "game_path_invalid", message: "游戏路径无效")
        }
        return path
    }

    static func detect(at input: String) -> (path: URL, version: String)? {
        guard !input.isEmpty else { return nil }
        let root = URL(filePath: input).standardizedFileURL
        for candidate in [root, root.appending(path: "Genshin Impact Game")] {
            guard let canonical = try? canonicalDirectory(candidate),
                  regularFile(canonical.appending(path: "YuanShen.exe")) else { continue }
            if let version = gameVersion(in: canonical) { return (canonical, version) }
        }
        return nil
    }

    static func audioLanguages(at root: URL) -> [String] {
        let files = [
            "zh-cn": "Audio_Chinese_pkg_version",
            "en-us": "Audio_English(US)_pkg_version",
            "ja-jp": "Audio_Japanese_pkg_version",
            "ko-kr": "Audio_Korean_pkg_version"
        ]
        let selected = files.compactMap { language, file in
            regularFile(root.appending(path: file)) ? language : nil
        }.sorted()
        return selected.isEmpty ? ["zh-cn"] : selected
    }

    static func safeTarget(root: URL, relativePath: String) throws -> URL {
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard SophonValidation.safePath(normalizedPath) else { throw unsafePath() }
        let canonicalRoot = try canonicalDirectory(root)
        let target = canonicalRoot.appending(path: normalizedPath).standardizedFileURL
        let rootPrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard target.path.hasPrefix(rootPrefix) else { throw unsafePath() }
        try PrivateFilesystem.rejectSymbolicLinks(in: target)

        var current = canonicalRoot
        let components = normalizedPath.split(separator: "/")
        for component in components.dropLast() {
            current.append(path: String(component))
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard isDirectory.boolValue, values.isSymbolicLink != true else { throw unsafePath() }
            }
        }
        return target
    }

    static func ensureParent(of target: URL) throws {
        let parent = target.deletingLastPathComponent()
        try PrivateFilesystem.ensureDirectory(parent)
    }

    static func writePrivate(_ data: Data, to url: URL) throws {
        try ensureParent(of: url)
        try PrivateFilesystem.requireRegularFileIfPresent(url)
        try data.write(to: url, options: .atomic)
        try PrivateFilesystem.setPrivateFilePermissions(url)
    }

    static func gameVersion(in root: URL) -> String? {
        for file in ["config.ini", ".mhg-version"] {
            let url = root.appending(path: file)
            guard let content = boundedText(url) else { continue }
            if file == ".mhg-version", let value = content.trimmingCharacters(in: .whitespacesAndNewlines).nonempty {
                if SophonValidation.isIdentifier(value) { return value }
                continue
            }
            for line in content.split(whereSeparator: \.isNewline) {
                let pair = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if pair.count == 2, pair[0] == "game_version",
                   let value = pair[1].nonempty, SophonValidation.isIdentifier(value) {
                    return value
                }
            }
        }
        return nil
    }

    private static func boundedText(_ url: URL) -> String? {
        guard regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize, size <= maximumVersionFileBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        while data.count < maximumVersionFileBytes {
            let remaining = maximumVersionFileBytes - data.count
            guard let chunk = try? handle.read(upToCount: min(64 * 1024, remaining)),
                  !chunk.isEmpty else { break }
            data.append(chunk)
        }
        if data.count == maximumVersionFileBytes,
           let extra = try? handle.read(upToCount: 1),
           !extra.isEmpty { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func regularFile(_ url: URL) -> Bool {
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: url)) != nil else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    static func canonicalDirectory(_ url: URL) throws -> URL {
        try PrivateFilesystem.rejectSymbolicLinks(in: url)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw unsafePath() }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func unsafePath() -> LauncherCoreError {
        LauncherCoreError(code: "unsafe_path", message: "资源路径不安全")
    }
}

enum FileDigest {
    static func md5Sync(_ url: URL) throws -> String {
        guard GameFilesystem.regularFile(url) else {
            throw LauncherCoreError(code: "file_missing", message: "待校验文件不存在")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = Insecure.MD5()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func md5(_ url: URL, progress: (@Sendable (Int64) async throws -> Void)? = nil) async throws -> String {
        guard GameFilesystem.regularFile(url) else {
            throw LauncherCoreError(code: "file_missing", message: "待校验文件不存在")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = Insecure.MD5()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
            try await progress?(Int64(data.count))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ url: URL) throws -> String {
        guard GameFilesystem.regularFile(url) else {
            throw LauncherCoreError(code: "file_missing", message: "待校验文件不存在")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
