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
        let chunks = Dictionary(uniqueKeysWithValues: assets.flatMap { asset in
            (asset.requiredChunks ?? asset.chunks).map { ($0.name, $0.size) }
        })
        let patches = Dictionary(uniqueKeysWithValues: patchAssets.map { ($0.patch.id, $0.patch.fileSize) })
        return pendingBytes + segments.reduce(0) { $0 + $1.size }
            + chunks.values.reduce(0, +) + patches.values.reduce(0, +)
    }

    func excludingLauncherManagedFiles() -> GameBuild {
        func managed(_ name: String) -> Bool {
            URL(filePath: name.replacingOccurrences(of: "\\", with: "/"))
                .lastPathComponent.lowercased() == "mhypbase.dll"
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

enum SophonValidation {
    static let maximumChunkOutput: Int64 = 256 * 1024 * 1024
    static func validate(_ build: GameBuild) throws -> GameBuild {
        guard isIdentifier(build.version) else { throw invalid() }
        var names = Set<String>()
        var chunks: [String: String] = [:]
        for asset in build.assets {
            guard safePath(asset.name), asset.size >= 0, isMD5(asset.md5) else { throw invalid() }
            guard names.insert(asset.name.lowercased()).inserted else { throw invalid() }
            for chunk in asset.chunks {
                guard isIdentifier(chunk.name), isMD5(chunk.decompressedMD5),
                      chunk.offset >= 0, chunk.size > 0, chunk.decompressedSize >= 0,
                      chunk.decompressedSize <= maximumChunkOutput,
                      chunk.offset <= asset.size,
                      chunk.decompressedSize <= asset.size - chunk.offset,
                      safeRemoteURL(chunk.url) else { throw invalid() }
                let signature = "\(chunk.size):\(chunk.decompressedSize):\(chunk.decompressedMD5.lowercased())"
                if let known = chunks[chunk.name], known != signature { throw invalid() }
                chunks[chunk.name] = signature
            }
        }
        for asset in build.patchAssets {
            let patch = asset.patch
            guard safePath(asset.name), asset.size >= 0, isMD5(asset.md5),
                  isIdentifier(patch.id), patch.fileSize > 0, patch.start >= 0,
                  patch.length > 0, patch.start <= patch.fileSize,
                  patch.length <= patch.fileSize - patch.start, safeRemoteURL(patch.url),
                  patch.originalName.isEmpty || safePath(patch.originalName) else { throw invalid() }
        }
        guard build.deprecatedFiles.allSatisfy(safePath) else { throw invalid() }
        return build.excludingLauncherManagedFiles()
    }

    static func safePath(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        return !normalized.isEmpty && !normalized.contains("\0") && !normalized.hasPrefix("/")
            && normalized.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private static func safeRemoteURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    private static func isMD5(_ value: String) -> Bool {
        value.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil
    }

    private static func isIdentifier(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$", options: .regularExpression) != nil
    }

    private static func invalid() -> LauncherCoreError {
        LauncherCoreError(code: "sophon_manifest_invalid", message: "Sophon 资源清单包含无效字段")
    }
}
