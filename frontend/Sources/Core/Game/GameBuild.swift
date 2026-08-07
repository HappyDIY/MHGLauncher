import Foundation

struct PackageSegment: Codable, Sendable, Equatable {
    let url: URL
    let md5: String
    let size: Int64
    let filename: String
}

struct SophonChunk: Codable, Sendable, Equatable {
    let name: String
    let decompressedMD5: String
    let offset: Int64
    let size: Int64
    let decompressedSize: Int64
    let url: URL
}

struct GameAsset: Codable, Sendable, Equatable {
    let name: String
    let size: Int64
    let md5: String
    let chunks: [SophonChunk]
    let requiredChunks: [SophonChunk]?
}

struct SophonPatch: Codable, Sendable, Equatable {
    let id: String
    let fileSize: Int64
    let start: Int64
    let length: Int64
    let originalName: String
    let url: URL
}

struct GamePatchAsset: Codable, Sendable, Equatable {
    let name: String
    let size: Int64
    let md5: String
    let patch: SophonPatch
}

struct GameBuild: Codable, Sendable, Equatable {
    let version: String
    let kind: String
    let pendingBytes: Int64
    let segments: [PackageSegment]
    let assets: [GameAsset]
    let patchAssets: [GamePatchAsset]
    let deprecatedFiles: [String]
    let baseAssets: [GameAsset]
    let repairAssets: [GameAsset]
    let isPredownload: Bool

    init(
        version: String,
        kind: String = "full",
        pendingBytes: Int64 = 0,
        segments: [PackageSegment] = [],
        assets: [GameAsset] = [],
        patchAssets: [GamePatchAsset] = [],
        deprecatedFiles: [String] = [],
        baseAssets: [GameAsset] = [],
        repairAssets: [GameAsset] = [],
        isPredownload: Bool = false
    ) {
        self.version = version
        self.kind = kind
        self.pendingBytes = pendingBytes
        self.segments = segments
        self.assets = assets
        self.patchAssets = patchAssets
        self.deprecatedFiles = deprecatedFiles
        self.baseAssets = baseAssets
        self.repairAssets = repairAssets
        self.isPredownload = isPredownload
    }

    var downloadSize: Int64 {
        var total = max(0, pendingBytes)
        var chunks: [String: Int64] = [:]
        for chunk in assets.flatMap({ $0.requiredChunks ?? $0.chunks }) {
            chunks[chunk.name.lowercased()] = chunk.size
        }
        var patches: [String: Int64] = [:]
        for patch in patchAssets {
            patches[patch.patch.id.lowercased()] = patch.patch.fileSize
        }
        for value in segments.map(\.size) + Array(chunks.values) + Array(patches.values) {
            total = Self.saturatingAdd(total, max(0, value))
        }
        return total
    }

    private static func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
        left > Int64.max - right ? Int64.max : left + right
    }

    func excludingLauncherManagedFiles() -> GameBuild {
        func managed(_ name: String) -> Bool {
            SophonValidation.isLauncherManagedPath(name)
        }
        return GameBuild(
            version: version,
            kind: kind,
            pendingBytes: pendingBytes,
            segments: segments,
            assets: assets.filter { !managed($0.name) },
            patchAssets: patchAssets.filter { !managed($0.name) },
            deprecatedFiles: deprecatedFiles.filter { !managed($0) },
            baseAssets: baseAssets.filter { !managed($0.name) },
            repairAssets: repairAssets.filter { !managed($0.name) },
            isPredownload: isPredownload
        )
    }
}

enum SophonVersion {
    static func compare(_ left: String, _ right: String) -> Int {
        let leftParts = left.split(separator: ".", omittingEmptySubsequences: false)
        let rightParts = right.split(separator: ".", omittingEmptySubsequences: false)
        let numeric = leftParts.allSatisfy(isNumeric) && rightParts.allSatisfy(isNumeric)
        guard numeric else {
            if left == right { return 0 }
            return left < right ? -1 : 1
        }
        for index in 0..<max(leftParts.count, rightParts.count) {
            let leftPart = index < leftParts.count ? normalizedNumber(leftParts[index]) : "0"
            let rightPart = index < rightParts.count ? normalizedNumber(rightParts[index]) : "0"
            if leftPart.count != rightPart.count {
                return leftPart.count < rightPart.count ? -1 : 1
            }
            if leftPart != rightPart { return leftPart < rightPart ? -1 : 1 }
        }
        return 0
    }

    private static func isNumeric(_ value: Substring) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }

    private static func normalizedNumber(_ value: Substring) -> String {
        let trimmed = value.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}

enum SophonValidation {
    static let maximumChunkOutput: Int64 = 256 * 1024 * 1024
    static let maximumAssetSize: Int64 = 32 * 1024 * 1024 * 1024
    static let maximumSegmentSize: Int64 = 32 * 1024 * 1024 * 1024
    static let maximumPatchSize: Int64 = 2 * 1024 * 1024 * 1024
    static let maximumBuildSize: Int64 = 128 * 1024 * 1024 * 1024

    static func validate(_ build: GameBuild) throws -> GameBuild {
        guard isIdentifier(build.version), isIdentifier(build.kind), build.pendingBytes >= 0,
              build.segments.count <= 200_000, build.assets.count <= 200_000,
              build.patchAssets.count <= 200_000, build.baseAssets.count <= 200_000,
              build.repairAssets.count <= 200_000, build.deprecatedFiles.count <= 200_000 else {
            throw invalid()
        }
        var assetNames = Set<String>()
        var baseNames = Set<String>()
        var repairNames = Set<String>()
        var segmentNames = Set<String>()
        var chunks: [String: String] = [:]
        for segment in build.segments {
            guard safePath(segment.filename), segment.filename.utf8.count <= 512,
                  segment.size > 0, segment.size <= maximumSegmentSize,
                  isMD5(segment.md5), safeRemoteURL(segment.url),
                  segmentNames.insert(canonicalPath(segment.filename)).inserted else { throw invalid() }
        }
        // 差分构建会同时携带旧版 base_assets、待写入的 assets 和完整 repair_assets，
        // 三个集合允许出现同名文件，但各自不能出现重复项。
        try validateAssets(build.assets, names: &assetNames, chunks: &chunks)
        try validateAssets(build.baseAssets, names: &baseNames, chunks: &chunks)
        try validateAssets(build.repairAssets, names: &repairNames, chunks: &chunks)

        var patchIDs: [String: Int64] = [:]
        var patchNames = Set<String>()
        var operationNames = Set(assetNames)
        for asset in build.patchAssets {
            let patch = asset.patch
            guard safePath(asset.name), asset.size >= 0, asset.size <= maximumAssetSize, isMD5(asset.md5),
                  isChunkName(patch.id), patch.fileSize > 0, patch.start >= 0,
                  patch.fileSize <= maximumPatchSize,
                  patch.length > 0, patch.start <= patch.fileSize,
                  patch.length <= patch.fileSize - patch.start, safeRemoteURL(patch.url),
                  patch.originalName.isEmpty
                    || (safePath(patch.originalName) && !isLauncherManagedPath(patch.originalName)) else {
                throw invalid()
            }
            guard patchNames.insert(canonicalPath(asset.name)).inserted else { throw invalid() }
            guard operationNames.insert(canonicalPath(asset.name)).inserted else { throw invalid() }
            guard patchIDs[patch.id.lowercased()] == nil else { throw invalid() }
            patchIDs[patch.id.lowercased()] = patch.fileSize
        }
        var deprecatedNames = Set<String>()
        for name in build.deprecatedFiles {
            guard safePath(name),
                  deprecatedNames.insert(canonicalPath(name)).inserted,
                  !operationNames.contains(canonicalPath(name)) else { throw invalid() }
        }
        guard build.downloadSize <= maximumBuildSize else { throw invalid() }
        return build.excludingLauncherManagedFiles()
    }

    private static func validateAssets(
        _ assets: [GameAsset],
        names: inout Set<String>,
        chunks: inout [String: String]
    ) throws {
        for asset in assets {
            guard safePath(asset.name), asset.size >= 0, asset.size <= maximumAssetSize,
                  isMD5(asset.md5), names.insert(canonicalPath(asset.name)).inserted else { throw invalid() }
            var localChunks: [String: SophonChunk] = [:]
            for chunk in asset.chunks {
                let signature = try validateChunk(chunk, assetSize: asset.size, known: &chunks)
                let key = chunk.name.lowercased()
                guard localChunks[key] == nil else { throw invalid() }
                localChunks[key] = chunk
                chunks[key] = signature
            }
            if let required = asset.requiredChunks {
                var requiredNames = Set<String>()
                for chunk in required {
                    let key = chunk.name.lowercased()
                    guard requiredNames.insert(key).inserted,
                          let canonical = localChunks[key], canonical == chunk else { throw invalid() }
                }
            }
        }
    }

    private static func validateChunk(
        _ chunk: SophonChunk,
        assetSize: Int64,
        known: inout [String: String]
    ) throws -> String {
        let key = chunk.name.lowercased()
        guard isChunkName(chunk.name), isMD5(chunk.decompressedMD5),
              chunk.offset >= 0, chunk.size > 0, chunk.size <= maximumChunkOutput,
              chunk.decompressedSize >= 0,
              chunk.decompressedSize <= maximumChunkOutput,
              chunk.offset <= assetSize,
              chunk.decompressedSize <= assetSize - chunk.offset,
              safeRemoteURL(chunk.url) else { throw invalid() }
        let signature = "\(chunk.size):\(chunk.decompressedSize):\(chunk.decompressedMD5.lowercased()):\(chunk.url.absoluteString)"
        if let value = known[key], value != signature { throw invalid() }
        return signature
    }

    static func safePath(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        return normalized.utf8.count <= 1024 && !normalized.isEmpty
            && !normalized.contains("\0") && !normalized.hasPrefix("/")
            && !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && normalized.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    static func canonicalPath(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    static func isLauncherManagedPath(_ value: String) -> Bool {
        guard let basename = canonicalPath(value).split(separator: "/").last else { return false }
        return [
            "mhypbase.dll",
            ".mhg-assets.json",
            ".mhg-integrity.json",
            ".mhg-staging-version",
            ".mhg-staging.json",
            ".mhg-version"
        ].contains(String(basename))
    }

    private static func safeRemoteURL(_ url: URL) -> Bool {
        url.absoluteString.utf8.count <= 16 * 1024
            && url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
            && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil && url.fragment == nil
    }

    static func isMD5(_ value: String) -> Bool {
        value.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil
    }

    static func isIdentifier(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$", options: .regularExpression) != nil
    }

    private static func isChunkName(_ value: String) -> Bool {
        value.utf8.count <= 512
            && value.range(of: "^[a-fA-F0-9]{16}(?:_[A-Za-z0-9._+-]+)?$", options: .regularExpression) != nil
    }

    private static func invalid() -> LauncherCoreError {
        LauncherCoreError(code: "sophon_manifest_invalid", message: "Sophon 资源清单包含无效字段")
    }
}
