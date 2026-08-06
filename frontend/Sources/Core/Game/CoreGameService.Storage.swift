import CryptoKit
import Darwin
import Foundation

private struct PredownloadMarker: Codable {
    let schema: Int
    let version: String
    let fingerprint: String
}

extension CoreGameService {
    func processAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if pid == Int32(ProcessInfo.processInfo.processIdentifier) { return true }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    func writeIntegrity(_ build: GameBuild, root: URL) throws {
        var assets: [String: [String: Any]] = [:]
        let canonical = build.repairAssets.isEmpty ? build.assets : build.repairAssets
        let patchAssets = build.repairAssets.isEmpty
            ? build.patchAssets.map { GameAsset(name: $0.name, size: $0.size, md5: $0.md5, chunks: [], requiredChunks: nil) }
            : []
        for asset in canonical + patchAssets {
            guard !SophonValidation.isLauncherManagedPath(asset.name) else { continue }
            let url = try GameFilesystem.safeTarget(root: root, relativePath: asset.name)
            guard GameFilesystem.regularFile(url),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  Int64(values.fileSize ?? -1) == asset.size else { continue }
            assets[asset.name.replacingOccurrences(of: "\\", with: "/")] = [
                "md5": asset.md5.lowercased(), "size": values.fileSize ?? 0,
                "mtime": values.contentModificationDate?.timeIntervalSince1970 ?? 0
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "assets": assets], options: [.sortedKeys])
        try GameFilesystem.writePrivate(data, to: root.appending(path: ".mhg-integrity.json"))
    }

    func outputSize(_ build: GameBuild) -> Int64 {
        func sum(_ values: [Int64]) -> Int64 {
            values.reduce(into: Int64(0)) { total, value in
                let size = max(0, value)
                total = total > Int64.max - size ? Int64.max : total + size
            }
        }

        let operationAssets = build.assets.isEmpty && build.patchAssets.isEmpty
            ? build.repairAssets : build.assets
        let outputs = operationAssets.reduce(into: [String: Int64]()) {
            $0[SophonValidation.canonicalPath($1.name)] = $1.size
        }.merging(build.patchAssets.reduce(into: [String: Int64]()) {
            $0[SophonValidation.canonicalPath($1.name)] = $1.size
        }) { _, new in new }
        let normalOutput = outputs.isEmpty ? build.downloadSize : sum(Array(outputs.values))
        let fallbackOutput = sum(build.repairAssets.map(\.size))
        return max(normalOutput, fallbackOutput)
    }

    func spaceResult(
        build: GameBuild,
        kind: JobKind,
        root: URL,
        detected: URL?
    ) throws -> SpaceCheckResult {
        let operationBytes = kind == .predownload
            ? build.downloadSize
            : max(build.downloadSize, outputSize(build))
        let stagedBytes: Int64
        if [.install, .update].contains(kind), let detected {
            stagedBytes = try directorySize(detected)
        } else {
            stagedBytes = 0
        }
        let required = saturatingAdd(
            saturatingAdd(operationBytes, stagedBytes),
            Self.spaceBufferBytes
        )
        let probe = existingAncestor(root)
        let values = try probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return SpaceCheckResult(available: available, required: required, sufficient: available >= required)
    }

    func directorySize(_ root: URL) throws -> Int64 {
        try PrivateFilesystem.rejectSymbolicLinksRecursively(in: root)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw LauncherCoreError(code: "game_size_invalid", message: "无法读取游戏目录大小")
        }
        var total: Int64 = 0
        while let entry = enumerator.nextObject() as? URL {
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else {
                throw LauncherCoreError(code: "game_size_invalid", message: "游戏目录包含不安全链接")
            }
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? -1)
            guard size >= 0, total <= Int64.max - size else {
                throw LauncherCoreError(code: "game_size_invalid", message: "游戏目录大小无效")
            }
            total += size
        }
        return total
    }

    func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
        left > Int64.max - right ? Int64.max : left + right
    }

    func existingAncestor(_ value: URL) -> URL {
        var current = value
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" {
            current.deleteLastPathComponent()
        }
        return current
    }

    func operationRoot(path: String, kind: JobKind, detected: URL?) throws -> URL {
        func directEntries(at directory: URL) throws -> [URL] {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            ) else {
                throw LauncherCoreError(code: "install_destination_invalid", message: "无法读取安装位置")
            }
            var entries: [URL] = []
            while let entry = enumerator.nextObject() as? URL {
                entries.append(entry)
                guard entries.count <= 4_096 else {
                    throw LauncherCoreError(code: "install_destination_too_large", message: "安装位置文件过多，已拒绝继续操作")
                }
            }
            return entries
        }

        let requested = URL(filePath: path).standardizedFileURL
        guard let detected else {
            guard kind == .install else { return requested }
            try PrivateFilesystem.rejectSymbolicLinks(in: requested)
            guard FileManager.default.fileExists(atPath: requested.path) else { return requested }
            let values = try requested.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw LauncherCoreError(code: "install_destination_invalid", message: "安装位置必须是普通目录")
            }
            let entries = try directEntries(at: requested)
            if !entries.isEmpty, requested.lastPathComponent != "Genshin Impact Game" {
                let nested = requested.appending(path: "Genshin Impact Game").standardizedFileURL
                try PrivateFilesystem.rejectSymbolicLinks(in: nested)
                guard !FileManager.default.fileExists(atPath: nested.path) else {
                    let nestedValues = try nested.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                    )
                    guard nestedValues.isDirectory == true, nestedValues.isSymbolicLink != true else {
                        throw LauncherCoreError(code: "install_destination_invalid", message: "安装位置必须是普通目录")
                    }
                    let nestedEntries = try directEntries(at: nested)
                    guard nestedEntries.isEmpty else {
                        throw LauncherCoreError(
                            code: "install_destination_not_empty",
                            message: "安装目录不为空，已拒绝覆盖其中的文件"
                        )
                    }
                    return nested
                }
                return nested
            }
            guard entries.isEmpty else {
                throw LauncherCoreError(code: "install_destination_not_empty", message: "安装目录不为空，已拒绝覆盖其中的文件")
            }
            return requested
        }
        return detected.standardizedFileURL
    }

    func predownloadCacheURL(root: URL, version: String) -> URL {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        return dataDirectory.appending(path: "GameDownloads/predownload/\(digest)/\(version)")
    }

    func existingPredownloadCache(root: URL, version: String) -> URL? {
        let cache = predownloadCacheURL(root: root, version: version)
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: cache)) != nil,
              let values = try? cache.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true else { return nil }
        return cache
    }

    func predownloadMarker(_ build: GameBuild) throws -> Data {
        try JSONEncoder.api.encode(PredownloadMarker(
            schema: 1,
            version: build.version,
            fingerprint: predownloadFingerprint(build)
        ))
    }

    func predownloadFingerprint(_ build: GameBuild) -> String {
        let data = (try? JSONEncoder.api.encode(build)) ?? Data(build.version.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func predownloadReady(_ build: GameBuild, root: URL?) throws -> Bool {
        guard let root else { return false }
        let cache = predownloadCacheURL(root: root, version: build.version)
        let markerURL = cache.appending(path: ".status.json")
        guard GameFilesystem.regularFile(markerURL),
              let values = try? markerURL.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 1024,
              let data = try? Data(contentsOf: markerURL),
              let value = try? JSONDecoder.api.decode(PredownloadMarker.self, from: data),
              value.schema == 1,
              value.version == build.version,
              value.fingerprint == predownloadFingerprint(build) else { return false }
        let patchValues = Dictionary(
            build.patchAssets.map { ($0.patch.id.lowercased(), ($0.patch.id, $0.patch.fileSize)) },
            uniquingKeysWith: { first, _ in first }
        )
        if !patchValues.isEmpty {
            return try patchValues.values.allSatisfy { name, size in
                try validPredownloadFile(cache, name: name, size: size)
            }
        }
        let chunks = Dictionary(
            build.assets.flatMap { $0.requiredChunks ?? $0.chunks }
                .map { ($0.name.lowercased(), ($0.name, $0.size)) },
            uniquingKeysWith: { first, _ in first }
        )
        return try chunks.values.allSatisfy { name, size in
            try validPredownloadFile(cache, name: name, size: size)
        }
    }

    func validPredownloadFile(_ root: URL, name: String, size: Int64) throws -> Bool {
        let target = try GameFilesystem.safeTarget(root: root, relativePath: name)
        guard GameFilesystem.regularFile(target),
              (try target.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(size) else { return false }
        return try CoreHash.xxHash64(file: target) == name.split(separator: "_", maxSplits: 1).first.map(String.init)?.lowercased()
    }

    func savedPath() async throws -> String? {
        try await database.read { db in
            try String.fetchOne(db, sql: "SELECT install_path FROM game_state WHERE id=1")
        }
    }

    func saveState(path: String, version: String, status: GameStatus) async throws {
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO game_state(id,install_path,version,status,updated_at) VALUES(1,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET install_path=excluded.install_path,version=excluded.version,
                status=excluded.status,updated_at=excluded.updated_at
                """, arguments: [path, version, status.rawValue, CoreDate.string(Date())])
        }
    }
}
