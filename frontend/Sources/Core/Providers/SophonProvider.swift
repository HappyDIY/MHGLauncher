import Foundation
import SwiftProtobuf

actor SophonProvider {
    private let transport: any HTTPTransport
    private let policy = HTTPSHostPolicy.sophon
    private var branchesCache: (Date, Branches)?
    private var buildCache: [String: (Date, GameBuild)] = [:]

    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    func build(installedVersion: String, audioLanguages: [String]) async throws -> GameBuild {
        let languages = normalizedLanguages(audioLanguages)
        let key = "main:\(installedVersion):\(languages.joined(separator: ","))"
        if let cached = cached(key) { return cached }
        let branches = try await branches()
        let remote = try await fullBuild(branch: branches.main, languages: languages, tag: nil)
        guard !installedVersion.isEmpty, installedVersion != remote.version else {
            cache(remote, key: key)
            return remote
        }
        let selected: GameBuild
        if branches.main.diffTags.contains(installedVersion),
           let patch = try? await patchBuild(branch: branches.main, version: installedVersion, languages: languages),
           patch.version == remote.version {
            selected = replacingRepairAssets(patch, with: remote.assets)
        } else if let local = try? await fullBuild(branch: branches.main, languages: languages, tag: installedVersion),
                  local.version == installedVersion {
            selected = diff(local: local, remote: remote)
        } else {
            selected = remote
        }
        cache(selected, key: key)
        return selected
    }

    func installedBuild(version: String, audioLanguages: [String]) async throws -> GameBuild {
        let languages = normalizedLanguages(audioLanguages)
        let key = "installed:\(version):\(languages.joined(separator: ","))"
        if let cached = cached(key) { return cached }
        let branch = try await branches()
        let value = try await fullBuild(branch: branch.main, languages: languages, tag: version)
        guard value.version == version else {
            throw LauncherCoreError(code: "sophon_installed_build_missing", message: "未找到当前版本的完整资源清单")
        }
        cache(value, key: key)
        return value
    }

    func predownloadBuild(installedVersion: String, audioLanguages: [String]) async throws -> GameBuild? {
        let languages = normalizedLanguages(audioLanguages)
        let availableBranches = try await branches()
        guard let branch = availableBranches.pre else { return nil }
        let key = "pre:\(installedVersion):\(languages.joined(separator: ","))"
        if let cached = cached(key) {
            guard installedVersion.isEmpty || SophonVersion.compare(cached.version, installedVersion) > 0 else {
                throw LauncherCoreError(code: "predownload_unavailable", message: "预下载版本不高于当前游戏版本")
            }
            return cached
        }
        let remote = try await fullBuild(branch: branch, languages: languages, tag: nil)
        guard installedVersion.isEmpty || SophonVersion.compare(remote.version, installedVersion) > 0 else {
            throw LauncherCoreError(code: "predownload_unavailable", message: "预下载版本不高于当前游戏版本")
        }
        let selected: GameBuild
        if branch.diffTags.contains(installedVersion),
           let patch = try? await patchBuild(branch: branch, version: installedVersion, languages: languages),
           patch.version == remote.version {
            selected = replacingRepairAssets(patch, with: remote.assets, predownload: true)
        } else if !installedVersion.isEmpty {
            let local = try await fullBuild(
                branch: availableBranches.main,
                languages: languages,
                tag: installedVersion
            )
            guard local.version == installedVersion else {
                throw LauncherCoreError(
                    code: "predownload_base_mismatch",
                    message: "当前游戏版本与本地资源清单不一致，无法计算预下载差分"
                )
            }
            selected = replacingRepairAssets(
                diff(local: local, remote: remote),
                with: remote.assets,
                predownload: true
            )
        } else {
            selected = replacingRepairAssets(remote, with: remote.repairAssets, predownload: true)
        }
        cache(selected, key: key)
        return selected
    }

    private func branches() async throws -> Branches {
        if let cache = branchesCache, Date().timeIntervalSince(cache.0) < 300 { return cache.1 }
        var components = URLComponents(string: "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGameBranches")!
        components.queryItems = [
            URLQueryItem(name: "game_ids[]", value: "1Z8W5NHUQb"),
            URLQueryItem(name: "launcher_id", value: "jGHBHlcOq1")
        ]
        let envelope: Envelope<GameBranchesData> = try await json(URLRequest(url: components.url!))
        guard let entry = envelope.data.gameBranches.first, let main = entry.main else {
            throw LauncherCoreError(code: "sophon_branch_missing", message: "未找到国服游戏分支")
        }
        let result = Branches(main: main, pre: entry.preDownload)
        branchesCache = (Date(), result)
        return result
    }

    private func fullBuild(branch: Branch, languages: [String], tag: String?) async throws -> GameBuild {
        var components = URLComponents(string: "https://downloader-api.mihoyo.com/downloader/sophon_chunk/api/getBuild")!
        var query = [
            URLQueryItem(name: "branch", value: branch.branch),
            URLQueryItem(name: "package_id", value: branch.packageID),
            URLQueryItem(name: "password", value: branch.password)
        ]
        if branch.branch.lowercased() != "predownload" {
            query.append(URLQueryItem(name: "tag", value: tag ?? branch.tag))
        }
        components.queryItems = query
        let envelope: Envelope<BuildData> = try await json(URLRequest(url: components.url!))
        let selected = envelope.data.manifests.filter {
            $0.matchingField == "game" || languages.contains($0.matchingField)
        }
        guard !selected.isEmpty else { throw emptyBuild() }
        var collected: [GameAsset] = []
        for item in selected { collected.append(contentsOf: try await parseAssets(item)) }
        guard !collected.isEmpty else { throw emptyBuild() }
        return try SophonValidation.validate(GameBuild(version: envelope.data.tag, assets: collected))
    }

    private func parseAssets(_ item: ManifestEntry) async throws -> [GameAsset] {
        let data = try await manifest(item, patch: false)
        let value = try SophonManifest(serializedBytes: data)
        guard value.assets.count <= 200_000 else {
            throw LauncherCoreError(code: "sophon_manifest_too_large", message: "Sophon 清单条目过多")
        }
        var chunkCount = 0
        for asset in value.assets {
            guard asset.assetChunks.count <= 200_000 - chunkCount else {
                throw LauncherCoreError(code: "sophon_manifest_too_large", message: "Sophon 清单条目过多")
            }
            chunkCount += asset.assetChunks.count
        }
        return value.assets.map { asset in
            GameAsset(
                name: asset.assetName,
                size: asset.assetSize,
                md5: asset.assetHashMd5,
                chunks: asset.assetChunks.map { chunk in
                    SophonChunk(
                        name: chunk.chunkName,
                        decompressedMD5: chunk.chunkDecompressedHashMd5,
                        offset: chunk.chunkOnFileOffset,
                        size: chunk.chunkSize,
                        decompressedSize: chunk.chunkSizeDecompressed,
                        url: try downloadURL(item.chunkDownload, name: chunk.chunkName)
                    )
                },
                requiredChunks: nil
            )
        }
    }

    private func patchBuild(branch: Branch, version: String, languages: [String]) async throws -> GameBuild {
        var request = URLRequest(url: URL(string: "https://downloader-api.mihoyo.com/downloader/sophon_chunk/api/getPatchBuild")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(branch)
        let envelope: Envelope<BuildData> = try await json(request)
        let selected = envelope.data.manifests.filter {
            $0.matchingField == "game" || languages.contains($0.matchingField)
        }
        guard !selected.isEmpty else { throw emptyBuild() }
        var assets: [GamePatchAsset] = []
        var deprecated: [String] = []
        for item in selected {
            let value = try PatchManifest(serializedBytes: await manifest(item, patch: true))
            for file in value.fileDatas {
                guard let info = file.patchesEntries.first(where: { $0.key == version })?.patchInfo else { continue }
                assets.append(GamePatchAsset(
                    name: file.fileName,
                    size: file.fileSize,
                    md5: file.fileHash,
                    patch: SophonPatch(
                        id: info.id,
                        fileSize: info.patchFileSize,
                        start: info.patchStartOffset,
                        length: info.patchLength,
                        originalName: info.originalFileName,
                        url: try downloadURL(item.diffDownload, name: info.id)
                    )
                ))
            }
            deprecated += value.deleteFilesEntries.first(where: { $0.key == version })?
                .deleteFiles.infos.map(\.name) ?? []
        }
        guard !assets.isEmpty || !deprecated.isEmpty else { throw emptyBuild() }
        return try SophonValidation.validate(GameBuild(
            version: envelope.data.tag,
            kind: "version_diff",
            patchAssets: assets,
            deprecatedFiles: deprecated
        ))
    }

    private func manifest(_ item: ManifestEntry, patch: Bool) async throws -> Data {
        let request = URLRequest(url: try downloadURL(item.manifestDownload, name: item.manifest.id))
        let response = try await transport.send(request, policy: policy, maximumBytes: 64 * 1024 * 1024)
        guard (200..<300).contains(response.statusCode) else {
            throw LauncherCoreError(code: "sophon_manifest_invalid", message: "Sophon 清单下载失败")
        }
        if !patch {
            let expected = item.manifest.id.replacingOccurrences(of: "manifest_", with: "")
                .split(separator: "_", maxSplits: 1).first.map(String.init)?.lowercased()
            guard CoreHash.xxHash64(response.data) == expected else {
                throw LauncherCoreError(code: "sophon_manifest_invalid", message: "Sophon 清单校验失败")
            }
        }
        let decoded = try Zstandard.decompress(response.data)
        guard CoreHash.md5(decoded) == item.manifest.checksum.lowercased() else {
            throw LauncherCoreError(code: "sophon_manifest_invalid", message: "Sophon 清单内容校验失败")
        }
        return decoded
    }

    private func json<T: Decodable>(_ request: URLRequest) async throws -> T where T: Sendable {
        let response = try await transport.send(request, policy: policy, maximumBytes: 64 * 1024 * 1024)
        guard (200..<300).contains(response.statusCode) else {
            throw LauncherCoreError(code: "mihoyo_error", message: "下载服务请求失败")
        }
        do {
            let value = try JSONDecoder.sophon().decode(T.self, from: response.data)
            if let envelope = value as? any RetcodeEnvelope, envelope.retcode != 0 {
                throw LauncherCoreError(code: "mihoyo_error", message: envelope.message.nonempty ?? "下载服务请求失败")
            }
            return value
        } catch let error as LauncherCoreError {
            throw error
        } catch {
            throw LauncherCoreError(code: "sophon_metadata_invalid", message: "下载服务元数据无效")
        }
    }

    private func downloadURL(_ value: Download, name: String) throws -> URL {
        let prefix = value.urlPrefix.hasSuffix("/") ? String(value.urlPrefix.dropLast()) : value.urlPrefix
        let separator = value.urlSuffix.isEmpty || value.urlSuffix.hasPrefix("?") ? "" : "?"
        guard let url = URL(string: "\(prefix)/\(name)\(separator)\(value.urlSuffix)"),
              url.absoluteString.utf8.count <= 16 * 1024,
              HTTPSHostPolicy.sophon.allows(url) else {
            throw LauncherCoreError(code: "sophon_manifest_invalid", message: "下载服务返回了无效资源地址")
        }
        return url
    }

    private func diff(local: GameBuild, remote: GameBuild) -> GameBuild {
        let localAssets = Dictionary(
            local.assets.map { (SophonValidation.canonicalPath($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let remoteNames = Set(remote.assets.map { SophonValidation.canonicalPath($0.name) })
        let assets = remote.assets.compactMap { remoteAsset -> GameAsset? in
            guard let localAsset = localAssets[SophonValidation.canonicalPath(remoteAsset.name)] else {
                return remoteAsset
            }
            guard localAsset.md5.lowercased() != remoteAsset.md5.lowercased() else { return nil }
            let known = Set(localAsset.chunks.map { $0.decompressedMD5.lowercased() })
            return GameAsset(
                name: remoteAsset.name,
                size: remoteAsset.size,
                md5: remoteAsset.md5,
                chunks: remoteAsset.chunks,
                requiredChunks: remoteAsset.chunks.filter { !known.contains($0.decompressedMD5.lowercased()) }
            )
        }
        return GameBuild(
            version: remote.version,
            kind: "version_diff_chunks",
            assets: assets,
            deprecatedFiles: local.assets.filter {
                !remoteNames.contains(SophonValidation.canonicalPath($0.name))
            }.map(\.name),
            baseAssets: local.assets,
            repairAssets: remote.assets
        )
    }

    private func replacingRepairAssets(
        _ build: GameBuild,
        with assets: [GameAsset],
        predownload: Bool? = nil
    ) -> GameBuild {
        GameBuild(
            version: build.version,
            kind: build.kind,
            pendingBytes: build.pendingBytes,
            segments: build.segments,
            assets: build.assets,
            patchAssets: build.patchAssets,
            deprecatedFiles: build.deprecatedFiles,
            baseAssets: build.baseAssets,
            repairAssets: assets,
            isPredownload: predownload ?? build.isPredownload
        )
    }

    private func normalizedLanguages(_ values: [String]) -> [String] {
        Array(Set(values.isEmpty ? ["zh-cn"] : values)).sorted()
    }

    private func cached(_ key: String) -> GameBuild? {
        guard let value = buildCache[key], Date().timeIntervalSince(value.0) < 300 else { return nil }
        return value.1
    }

    private func cache(_ value: GameBuild, key: String) { buildCache[key] = (Date(), value) }

    private func emptyBuild() -> LauncherCoreError {
        LauncherCoreError(code: "sophon_build_empty", message: "Sophon 构建未包含所需资源清单")
    }
}

private protocol RetcodeEnvelope {
    var retcode: Int { get }
    var message: String { get }
}

private struct Envelope<Value: Codable & Sendable>: Codable, Sendable, RetcodeEnvelope {
    let retcode: Int
    let message: String
    let data: Value
}

private struct Branches: Sendable {
    let main: Branch
    let pre: Branch?
}

private struct GameBranchesData: Codable, Sendable {
    let gameBranches: [GameBranchEntry]
}

private struct GameBranchEntry: Codable, Sendable {
    let main: Branch?
    let preDownload: Branch?
}

private struct Branch: Codable, Sendable {
    let branch: String
    let packageID: String
    let password: String
    let tag: String
    let diffTags: [String]
}

private struct BuildData: Codable, Sendable {
    let tag: String
    let manifests: [ManifestEntry]
}

private struct ManifestEntry: Codable, Sendable {
    let matchingField: String
    let manifest: ManifestInfo
    let manifestDownload: Download
    let chunkDownload: Download
    let diffDownload: Download
}

private struct ManifestInfo: Codable, Sendable {
    let id: String
    let checksum: String
}

private struct Download: Codable, Sendable {
    let urlPrefix: String
    let urlSuffix: String
}

private extension JSONDecoder {
    static func sophon() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

extension HTTPSHostPolicy {
    static let sophon = HTTPSHostPolicy(
        exactHosts: ["hyp-api.mihoyo.com", "downloader-api.mihoyo.com"],
        suffixes: ["mihoyo.com", "hoyoverse.com"]
    )
}
