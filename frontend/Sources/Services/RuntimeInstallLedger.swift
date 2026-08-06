import CryptoKit
import Darwin
import Foundation

struct RuntimeInstallRecord: Codable, Equatable {
    let schemaVersion: Int
    let tag: String
    let appVersion: String
    let manifestDigest: String
    let scope: RuntimeInstallScope
    let requiredPaths: [String]
}

enum RuntimeInstallLedger {
    static let markerName = ".runtime-install.json"

    static func write(
        manifest: RuntimeManifest,
        manifestData: Data,
        scope: RuntimeInstallScope,
        root: URL
    ) throws {
        let paths = requiredPaths(in: manifest, scope: scope)
        guard pathsAreSafe(paths, under: root) else {
            throw RuntimeInstallError.invalidManifest
        }
        let record = RuntimeInstallRecord(
            schemaVersion: 3,
            tag: manifest.tag,
            appVersion: manifest.appVersion,
            manifestDigest: digest(manifestData),
            scope: scope,
            requiredPaths: paths
        )
        let data = try JSONEncoder().encode(record)
        try GameFilesystem.writePrivate(data, to: root.appending(path: markerName))
    }

    static func isReady(
        root: URL,
        tag: String,
        appVersion: String,
        scope: RuntimeInstallScope
    ) -> Bool {
        guard (try? validateTree(at: root)) != nil else { return false }
        let marker = root.appending(path: markerName)
        if GameFilesystem.regularFile(marker),
           let values = try? marker.resourceValues(forKeys: [.fileSizeKey]),
           (values.fileSize ?? 0) <= 1024 * 1024,
           let data = try? Data(contentsOf: marker, options: .mappedIfSafe),
           let record = try? JSONDecoder().decode(RuntimeInstallRecord.self, from: data),
           record.schemaVersion == 3,
           record.tag == tag,
           record.appVersion == appVersion,
           record.manifestDigest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
           record.scope == scope || record.scope == .game,
           record.requiredPaths.count <= 4_096,
           !record.requiredPaths.isEmpty {
        let paths = scope == .core
            ? record.requiredPaths.filter { !RuntimeManifest.canonicalPath($0).hasPrefix("game-runtime/") }
            : record.requiredPaths
        return !paths.isEmpty && pathsAreSafe(paths, under: root)
        }
        // 兼容旧式 .core-complete/.game-complete 标记：
        // schema v2 之前安装的运行时没有 ledger，按标记与关键文件判定就绪。
        return legacyReady(root: root, scope: scope)
    }

    private static func legacyReady(root: URL, scope: RuntimeInstallScope) -> Bool {
        let marker = root.appending(path: scope == .core ? ".core-complete" : ".game-complete")
        guard GameFilesystem.regularFile(marker) else { return false }
        let paths = scope == .core
            ? ["tools/hpatchz"]
            : ["game-runtime/wine/bin/wine", "game-runtime/assets/mhypbase.dll"]
        return pathsAreSafe(paths, under: root)
    }

    static func requiredPaths(
        in manifest: RuntimeManifest,
        scope: RuntimeInstallScope
    ) -> [String] {
        if scope == .game { return manifest.requiredPaths }
        return manifest.requiredPaths.filter { !RuntimeManifest.canonicalPath($0).hasPrefix("game-runtime/") }
    }

    static func validateTree(at root: URL) throws {
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: root)) != nil,
              let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                  options: []
              ) else {
            throw RuntimeInstallError.archiveTraversal("运行时目录不安全")
        }
        while let entry = enumerator.nextObject() as? URL {
            var info = stat()
            guard lstat(entry.path, &info) == 0 else {
                throw RuntimeInstallError.archiveTraversal("运行时目录无法读取")
            }
            let mode = info.st_mode & S_IFMT
            if mode == S_IFLNK {
                guard validateContainedSymlink(at: entry, under: root) else {
                    throw RuntimeInstallError.archiveTraversal("运行时目录包含不安全链接")
                }
            } else if mode != S_IFDIR && mode != S_IFREG {
                throw RuntimeInstallError.archiveTraversal("运行时目录包含特殊文件")
            }
        }
    }

    static func pathsAreSafe(_ paths: [String], under root: URL) -> Bool {
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: root)) != nil,
              let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else { return false }
        return paths.allSatisfy { relative in
            let normalized = RuntimeManifest.normalizedPath(relative)
            guard RuntimeManifest.isSafeRelativePath(normalized) else { return false }
            var current = root
            let components = normalized.split(separator: "/")
            for (index, component) in components.enumerated() {
                current.append(path: String(component))
                var info = stat()
                guard lstat(current.path, &info) == 0 else { return false }
                let mode = info.st_mode & S_IFMT
                if mode == S_IFLNK {
                    guard index == components.count - 1,
                          validateContainedSymlink(at: current, under: root) else { return false }
                } else if mode != S_IFDIR && mode != S_IFREG {
                    return false
                }
            }
            return true
        }
    }

    static func isContainedSymlinkTarget(_ target: String, entry: String) -> Bool {
        let normalizedTarget = RuntimeManifest.normalizedPath(target)
        let normalizedEntry = RuntimeManifest.normalizedPath(entry)
        guard !normalizedTarget.isEmpty,
              normalizedTarget.utf8.count <= 1024,
              !normalizedTarget.hasPrefix("/"),
              !normalizedTarget.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              RuntimeManifest.isSafeRelativePath(normalizedEntry) else { return false }
        if RuntimeManifest.canonicalPath(normalizedEntry) == "game-runtime/wine/bin/wineboot",
           normalizedTarget != "wine" {
            return false
        }
        var components = normalizedEntry.split(separator: "/").dropLast().map(String.init)
        for component in normalizedTarget.split(separator: "/", omittingEmptySubsequences: false) {
            if component.isEmpty || component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else { return false }
                components.removeLast()
            } else {
                components.append(String(component))
            }
        }
        let resolved = components.joined(separator: "/")
        return RuntimeManifest.isSafeRelativePath(resolved)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func relativePath(_ entry: URL, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let entryPath = entry.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard entryPath.hasPrefix(prefix) else { return nil }
        return String(entryPath.dropFirst(prefix.count))
    }

    private static func validateContainedSymlink(at entry: URL, under root: URL) -> Bool {
        guard let relative = relativePath(entry, under: root),
              let target = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path),
              isContainedSymlinkTarget(target, entry: relative) else { return false }
        let normalizedTarget = RuntimeManifest.normalizedPath(target)
        let resolved = entry.deletingLastPathComponent()
            .appending(path: normalizedTarget)
            .standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard resolved.path.hasPrefix(prefix) else { return false }
        var info = stat()
        guard lstat(resolved.path, &info) == 0 else { return false }
        let mode = info.st_mode & S_IFMT
        return mode == S_IFREG || mode == S_IFDIR
    }
}
