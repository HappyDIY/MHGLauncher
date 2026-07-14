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
            schemaVersion: 2,
            tag: manifest.tag,
            appVersion: manifest.appVersion,
            manifestDigest: digest(manifestData),
            scope: scope,
            requiredPaths: paths
        )
        let data = try JSONEncoder().encode(record)
        try data.write(to: root.appending(path: markerName), options: .atomic)
    }

    static func isReady(
        root: URL,
        tag: String,
        appVersion: String,
        scope: RuntimeInstallScope
    ) -> Bool {
        let marker = root.appending(path: markerName)
        if let data = try? Data(contentsOf: marker, options: .mappedIfSafe),
           let record = try? JSONDecoder().decode(RuntimeInstallRecord.self, from: data),
           record.schemaVersion == 2,
           record.tag == tag,
           record.appVersion == appVersion,
           record.manifestDigest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
           record.scope == scope || record.scope == .game,
           !record.requiredPaths.isEmpty {
            let paths = scope == .core
                ? record.requiredPaths.filter { !$0.hasPrefix("game-runtime/") }
                : record.requiredPaths
            return !paths.isEmpty && pathsAreSafe(paths, under: root)
        }
        // 兼容旧式 .core-complete/.game-complete 标记：
        // schema v2 之前安装的运行时没有 ledger，按标记与关键文件判定就绪。
        return legacyReady(root: root, scope: scope)
    }

    private static func legacyReady(root: URL, scope: RuntimeInstallScope) -> Bool {
        let marker = root.appending(path: scope == .core ? ".core-complete" : ".game-complete")
        guard FileManager.default.fileExists(atPath: marker.path) else { return false }
        let paths = scope == .core
            ? ["node/bin/node", "backend/app/node_modules", "backend/hpatchz"]
            : ["game-runtime/wine/bin/wine", "game-runtime/assets/mhypbase.dll"]
        return pathsAreSafe(paths, under: root)
    }

    static func requiredPaths(
        in manifest: RuntimeManifest,
        scope: RuntimeInstallScope
    ) -> [String] {
        if scope == .game { return manifest.requiredPaths }
        return manifest.requiredPaths.filter { !$0.hasPrefix("game-runtime/") }
    }

    static func pathsAreSafe(_ paths: [String], under root: URL) -> Bool {
        paths.allSatisfy { relative in
            guard RuntimeManifest.isSafeRelativePath(relative) else { return false }
            var current = root
            for component in relative.split(separator: "/") {
                current.append(path: String(component))
                var info = stat()
                guard lstat(current.path, &info) == 0,
                      info.st_mode & S_IFMT != S_IFLNK else { return false }
            }
            return true
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
