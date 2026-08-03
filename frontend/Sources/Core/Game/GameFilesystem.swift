import CryptoKit
import Foundation

enum GameFilesystem {
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
            FileManager.default.fileExists(atPath: root.appending(path: file).path) ? language : nil
        }.sorted()
        return selected.isEmpty ? ["zh-cn"] : selected
    }

    static func safeTarget(root: URL, relativePath: String) throws -> URL {
        guard SophonValidation.safePath(relativePath) else { throw unsafePath() }
        let canonicalRoot = try canonicalDirectory(root)
        let target = canonicalRoot.appending(path: relativePath).standardizedFileURL
        let rootPrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard target.path.hasPrefix(rootPrefix) else { throw unsafePath() }

        var current = canonicalRoot
        let components = relativePath.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
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
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try PrivateFilesystem.ensureDirectory(parent)
    }

    static func writePrivate(_ data: Data, to url: URL) throws {
        try ensureParent(of: url)
        try data.write(to: url, options: .atomic)
        try PrivateFilesystem.setPrivateFilePermissions(url)
    }

    static func gameVersion(in root: URL) -> String? {
        for file in ["config.ini", ".mhg-version"] {
            let url = root.appending(path: file)
            guard regularFile(url), let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if file == ".mhg-version", let value = content.trimmingCharacters(in: .whitespacesAndNewlines).nonempty {
                return value
            }
            for line in content.split(whereSeparator: \.isNewline) {
                let pair = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if pair.count == 2, pair[0] == "game_version", let value = pair[1].nonempty { return value }
            }
        }
        return nil
    }

    static func regularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    static func canonicalDirectory(_ url: URL) throws -> URL {
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
