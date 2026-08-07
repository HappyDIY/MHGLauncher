import CryptoKit
import Darwin
import Foundation

struct GameInstallResume {
    let destination: URL
    let stage: URL
    let version: String
}

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
        var assets = readIntegrityEntries(root: root)
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
            let name = SophonValidation.canonicalPath(asset.name)
            var entry: [String: Any] = [
                "md5": asset.md5.lowercased(), "size": values.fileSize ?? 0
            ]
            if let modifiedAt = modificationTimeNanoseconds(url) {
                entry["mtime_ns"] = String(modifiedAt)
            } else {
                entry["mtime"] = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            }
            assets[name] = entry
        }
        for name in build.deprecatedFiles {
            assets.removeValue(forKey: SophonValidation.canonicalPath(name))
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "assets": assets], options: [.sortedKeys])
        try GameFilesystem.writePrivate(data, to: root.appending(path: ".mhg-integrity.json"))
    }

    private func readIntegrityEntries(root: URL) -> [String: [String: Any]] {
        let url = root.appending(path: ".mhg-integrity.json")
        guard GameFilesystem.regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["version"] as? NSNumber)?.intValue == 1,
              let rawAssets = object["assets"] as? [String: [String: Any]] else { return [:] }
        return rawAssets.reduce(into: [String: [String: Any]]()) { result, pair in
            guard SophonValidation.safePath(pair.key),
                  let md5 = pair.value["md5"] as? String,
                  let size = pair.value["size"] as? NSNumber,
                  SophonValidation.isMD5(md5), size.int64Value >= 0 else { return }
            let hasSeconds = (pair.value["mtime"] as? NSNumber)?.doubleValue.isFinite == true
            let hasNanoseconds = (pair.value["mtime_ns"] as? String).flatMap(Int64.init) != nil
            guard hasSeconds || hasNanoseconds else { return }
            result[SophonValidation.canonicalPath(pair.key)] = pair.value
        }
    }

    private func modificationTimeNanoseconds(_ url: URL) -> Int64? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let seconds = Int64(info.st_mtimespec.tv_sec)
        let nanoseconds = Int64(info.st_mtimespec.tv_nsec)
        guard seconds <= (Int64.max - nanoseconds) / 1_000_000_000 else { return nil }
        return seconds * 1_000_000_000 + nanoseconds
    }

    func writeAssetNames(_ build: GameBuild, root: URL) throws {
        let canonical = build.repairAssets.isEmpty ? build.assets : build.repairAssets
        guard !canonical.isEmpty else { return }
        let data = try JSONEncoder.api.encode(canonical.map(\.name))
        try GameFilesystem.writePrivate(data, to: root.appending(path: ".mhg-assets.json"))
    }

    func outputSize(_ build: GameBuild) -> Int64 {
        func sum(_ values: [Int64]) -> Int64 {
            values.reduce(into: Int64(0)) { total, value in
                let size = max(0, value)
                total = total > Int64.max - size ? Int64.max : total + size
            }
        }

        let outputs = build.assets.reduce(into: [String: Int64]()) {
            $0[SophonValidation.canonicalPath($1.name)] = $1.size
        }.merging(build.patchAssets.reduce(into: [String: Int64]()) {
            $0[SophonValidation.canonicalPath($1.name)] = $1.size
        }) { _, new in new }
        return outputs.isEmpty ? build.downloadSize : sum(Array(outputs.values))
    }

    func spaceResult(
        build: GameBuild,
        kind: JobKind,
        root: URL,
        detected: URL?
    ) throws -> SpaceCheckResult {
        let operationBytes = kind == .predownload ? build.downloadSize : outputSize(build)
        let cachedBytes = try cachedDownloadBytes(build, root: root)
        let required = saturatingAdd(max(0, operationBytes - cachedBytes), Self.spaceBufferBytes)
        let probe = existingAncestor(root)
        let values = try probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return SpaceCheckResult(available: available, required: required, sufficient: available >= required)
    }

    func prepareInstalledBuild(
        _ build: GameBuild,
        root: URL?,
        installedVersion: String
    ) -> GameBuild {
        guard let root, installedVersion == build.version, !build.assets.isEmpty else { return build }
        let index = integrityIndex(root: root)
        let packageHashes = packageHashes(root: root)
        let invalid = build.assets.filter { !fastValid($0, root: root, index: index, packageHashes: packageHashes) }
        return GameBuild(
            version: build.version,
            kind: "package_repair",
            pendingBytes: build.pendingBytes,
            segments: build.segments,
            assets: invalid,
            patchAssets: build.patchAssets,
            deprecatedFiles: build.deprecatedFiles,
            baseAssets: build.baseAssets,
            repairAssets: build.assets,
            isPredownload: build.isPredownload
        )
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

    private func cachedDownloadBytes(_ build: GameBuild, root: URL) throws -> Int64 {
        guard let cache = existingPredownloadCache(root: root, version: build.version) else { return 0 }
        if !build.patchAssets.isEmpty {
            let patches = Dictionary(
                build.patchAssets.map { ($0.patch.id.lowercased(), ($0.patch.id, $0.patch.fileSize)) },
                uniquingKeysWith: { first, _ in first }
            )
            return try patches.values.reduce(into: Int64(0)) { total, value in
                if try validPredownloadFile(cache, name: value.0, size: value.1) {
                    total = saturatingAdd(total, value.1)
                }
            }
        }
        let chunks = Dictionary(
            build.assets.flatMap { $0.requiredChunks ?? $0.chunks }
                .map { ($0.name.lowercased(), ($0.name, $0.size)) },
            uniquingKeysWith: { first, _ in first }
        )
        return try chunks.values.reduce(into: Int64(0)) { total, value in
            if try validPredownloadFile(cache, name: value.0, size: value.1) {
                total = saturatingAdd(total, value.1)
            }
        }
    }

    private struct IntegrityEntry {
        let md5: String
        let size: Int64
        let modifiedAt: TimeInterval?
        let modifiedAtNanoseconds: Int64?
    }

    private func fastValid(
        _ asset: GameAsset,
        root: URL,
        index: [String: IntegrityEntry],
        packageHashes: [String: String]
    ) -> Bool {
        guard let target = try? GameFilesystem.safeTarget(root: root, relativePath: asset.name),
              GameFilesystem.regularFile(target),
              (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(asset.size) else {
            return false
        }
        let key = SophonValidation.canonicalPath(asset.name)
        if let entry = index[key] ?? index[asset.name.replacingOccurrences(of: "\\", with: "/")] {
            let modifiedAt = (try? target.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let timeMatches: Bool
            if let expected = entry.modifiedAtNanoseconds {
                timeMatches = modificationTimeNanoseconds(target) == expected
            } else {
                timeMatches = entry.modifiedAt == modifiedAt
            }
            return entry.md5 == asset.md5.lowercased()
                && entry.size == asset.size
                && timeMatches
        }
        return packageHashes[key] == asset.md5.lowercased()
    }

    private func integrityIndex(root: URL) -> [String: IntegrityEntry] {
        let url = root.appending(path: ".mhg-integrity.json")
        guard GameFilesystem.regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["version"] as? NSNumber)?.intValue == 1,
              let assets = object["assets"] as? [String: [String: Any]] else { return [:] }
        return assets.reduce(into: [String: IntegrityEntry]()) { result, pair in
            guard let md5 = pair.value["md5"] as? String,
                  let size = pair.value["size"] as? NSNumber,
                  SophonValidation.isMD5(md5), size.int64Value >= 0 else { return }
            if let modifiedAt = pair.value["mtime"] as? NSNumber, modifiedAt.doubleValue.isFinite {
                result[SophonValidation.canonicalPath(pair.key)] = IntegrityEntry(
                    md5: md5.lowercased(), size: size.int64Value,
                    modifiedAt: modifiedAt.doubleValue, modifiedAtNanoseconds: nil
                )
                return
            }
            guard let modifiedAt = pair.value["mtime_ns"] as? String,
                  let modifiedAtNanoseconds = Int64(modifiedAt) else {
                return
            }
            result[SophonValidation.canonicalPath(pair.key)] = IntegrityEntry(
                md5: md5.lowercased(), size: size.int64Value,
                modifiedAt: nil, modifiedAtNanoseconds: modifiedAtNanoseconds
            )
        }
    }

    private func packageHashes(root: URL) -> [String: String] {
        let filenames = [
            "pkg_version", "Audio_Chinese_pkg_version", "Audio_English(US)_pkg_version",
            "Audio_Japanese_pkg_version", "Audio_Korean_pkg_version"
        ]
        return filenames.reduce(into: [String: String]()) { result, filename in
            let url = root.appending(path: filename)
            guard GameFilesystem.regularFile(url),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= 8 * 1024 * 1024,
                  let source = try? String(contentsOf: url, encoding: .utf8) else { return }
            for line in source.split(whereSeparator: \.isNewline) {
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let name = object["remoteName"] as? String,
                      let md5 = object["md5"] as? String,
                      SophonValidation.isMD5(md5) else { continue }
                result[SophonValidation.canonicalPath(name)] = md5.lowercased()
            }
        }
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

    func operationRoot(
        path: String,
        kind: JobKind,
        detected: URL?,
        resumeDestination: URL? = nil
    ) throws -> URL {
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

        if let resumeDestination { return resumeDestination.standardizedFileURL }
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

    func installResume(for requested: URL) -> GameInstallResume? {
        let requested = requested.standardizedFileURL
        if let destination = stagingDestination(for: requested),
           let resume = readInstallResume(stage: requested, destination: destination) {
            return resume
        }
        var destinations = [requested]
        if requested.lastPathComponent != "Genshin Impact Game" {
            destinations.append(requested.appending(path: "Genshin Impact Game"))
        }
        for destination in destinations {
            if let resume = readInstallResume(stage: destination, destination: destination) {
                return resume
            }
        }
        return destinations
            .flatMap { stagingDirectories(for: $0) }
            .max { $0.modified < $1.modified }
            .map { $0.resume }
    }

    private func stagingDirectories(for destination: URL) -> [(resume: GameInstallResume, modified: Date)] {
        let parent = destination.deletingLastPathComponent()
        let prefixes = [
            ".\(destination.lastPathComponent).mhg-staging-",
            "\(destination.lastPathComponent).mhg-staging-"
        ]
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: parent)) != nil,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: parent,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                  options: []
              ) else { return [] }
        return entries.compactMap { entry in
            guard prefixes.contains(where: { entry.lastPathComponent.hasPrefix($0) }),
                  let values = try? entry.resourceValues(
                      forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
                  ),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let resume = readInstallResume(stage: entry, destination: destination) else { return nil }
            return (resume, values.contentModificationDate ?? .distantPast)
        }
    }

    private func readInstallResume(stage: URL, destination: URL) -> GameInstallResume? {
        guard (try? PrivateFilesystem.rejectSymbolicLinksRecursively(in: stage)) != nil else { return nil }
        let marker = stage.appending(path: ".mhg-staging.json")
        let versionMarker = stage.appending(path: ".mhg-staging-version")
        guard GameFilesystem.regularFile(marker),
              GameFilesystem.regularFile(versionMarker),
              let values = try? marker.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 16 * 1024,
              let data = try? Data(contentsOf: marker),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["schema"] as? NSNumber)?.intValue == 1,
              let owner = object["owner"] as? String, UUID(uuidString: owner) != nil,
              let pid = object["pid"] as? NSNumber,
              pid.int64Value > 0, pid.int64Value <= Int64(Int32.max),
              let kind = object["kind"] as? String, kind == JobKind.install.rawValue,
              let recordedDestination = object["destination"] as? String,
              URL(filePath: recordedDestination).standardizedFileURL == destination.standardizedFileURL,
              let version = object["version"] as? String,
              SophonValidation.isIdentifier(version),
              let markerVersion = try? String(contentsOf: versionMarker, encoding: .utf8),
              markerVersion.trimmingCharacters(in: .whitespacesAndNewlines) == version else { return nil }
        return GameInstallResume(destination: destination.standardizedFileURL, stage: stage, version: version)
    }

    private func stagingDestination(for stage: URL) -> URL? {
        let name = stage.lastPathComponent
        guard let range = name.range(of: ".mhg-staging-"), range.lowerBound != name.startIndex else {
            return nil
        }
        let raw = String(name[..<range.lowerBound])
        let destinationName = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
        guard !destinationName.isEmpty else { return nil }
        return stage.deletingLastPathComponent().appending(path: destinationName).standardizedFileURL
    }

    func downloadCacheScope(root: URL) -> URL {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        return dataDirectory.appending(path: "GameDownloads/predownload/\(digest)")
    }

    func downloadCacheScopes(root: URL) -> [URL] {
        [
            downloadCacheScope(root: root),
            dataDirectory.appending(path: "downloads/\(legacyCacheDigest(root: root))")
        ]
    }

    func predownloadCacheURL(root: URL, version: String) -> URL {
        downloadCacheScope(root: root).appending(path: version)
    }

    func downloadCache(root: URL, version: String) throws -> URL {
        let candidates = [predownloadCacheURL(root: root, version: version), legacyPredownloadCacheURL(root: root, version: version)]
        if let existing = candidates.first(where: isCacheDirectory) { return existing }
        let cache = candidates[0]
        try PrivateFilesystem.ensureDirectory(cache)
        return cache
    }

    func existingPredownloadCache(root: URL, version: String) -> URL? {
        [predownloadCacheURL(root: root, version: version), legacyPredownloadCacheURL(root: root, version: version)]
            .first(where: isCacheDirectory)
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
        guard let cache = existingPredownloadCache(root: root, version: build.version) else { return false }
        let markerURL = cache.appending(path: ".status.json")
        let currentMarker = GameFilesystem.regularFile(markerURL)
            && (try? markerURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { $0 <= 1024 } == true
            && (try? Data(contentsOf: markerURL)).flatMap { try? JSONDecoder.api.decode(PredownloadMarker.self, from: $0) }
                .map { $0.schema == 1 && $0.version == build.version && $0.fingerprint == predownloadFingerprint(build) } == true
        guard currentMarker || legacyPredownloadReady(cache: cache, build: build) else { return false }
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

    private func legacyPredownloadCacheURL(root: URL, version: String) -> URL {
        dataDirectory.appending(path: "downloads/\(legacyCacheDigest(root: root))/\(version)")
    }

    private func legacyCacheDigest(root: URL) -> String {
        SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map {
            String(format: "%02x", $0)
        }.joined().prefix(16).description
    }

    private func isCacheDirectory(_ cache: URL) -> Bool {
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: cache)) != nil,
              let values = try? cache.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func legacyPredownloadReady(cache: URL, build: GameBuild) -> Bool {
        let marker = cache.appending(path: ".mhg-predownload-status.json")
        guard GameFilesystem.regularFile(marker),
              let values = try? marker.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 1024,
              let data = try? Data(contentsOf: marker),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag"] as? String, !tag.isEmpty, tag == build.version,
              let digest = object["manifest_digest"] as? String,
              digest.count == 64,
              digest.unicodeScalars.allSatisfy({ scalar in
                  (48...57).contains(scalar.value) || (65...70).contains(scalar.value) || (97...102).contains(scalar.value)
              }),
              digest.lowercased() == legacyPredownloadFingerprint(build),
              let totalChunks = object["total_chunks"] as? NSNumber,
              totalChunks.doubleValue.isFinite,
              totalChunks.doubleValue >= 0,
              totalChunks.doubleValue.rounded() == totalChunks.doubleValue,
              (object["finished"] as? Bool) == true else { return false }
        return true
    }

    private func legacyPredownloadFingerprint(_ build: GameBuild) -> String {
        var files: [String: (name: String, size: Int64)] = [:]
        if !build.patchAssets.isEmpty {
            for value in build.patchAssets where files[value.patch.id] == nil {
                files[value.patch.id] = (value.patch.id, value.patch.fileSize)
            }
        } else {
            for chunk in build.assets.flatMap({ $0.requiredChunks ?? $0.chunks }) where files[chunk.name] == nil {
                files[chunk.name] = (chunk.name, chunk.size)
            }
        }
        let entries = files.values.sorted { $0.name < $1.name }.map { value in
            "{\"name\":\(legacyJSONString(value.name)),\"size\":\(value.size)}"
        }.joined(separator: ",")
        let payload = "{\"version\":\(legacyJSONString(build.version)),\"files\":[\(entries)]}"
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func legacyJSONString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
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
