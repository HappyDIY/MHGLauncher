import Darwin
import Foundation
import GRDB

actor CoreGameService {
    static let spaceBufferBytes: Int64 = 1024 * 1024 * 1024

    let database: CoreDatabase
    private let provider: any GameProvider
    private let jobs: GameJobCoordinator
    private let operationCoordinator: GameOperationCoordinator
    let dataDirectory: URL
    private let fixtureMode: Bool
    private let hpatchzURL: URL
    private let processRunner: any CoreProcessRunning
    private let onInstalled: (@Sendable (String) async -> Void)?
    private var speedLimitKB = 0
    private var throttleTokens = 0.0
    private var throttleUpdatedAt = Date()
    private var shuttingDown = false
    init(
        database: CoreDatabase,
        provider: any GameProvider,
        jobs: GameJobCoordinator,
        dataDirectory: URL,
        fixtureMode: Bool,
        hpatchzURL: URL,
        processRunner: any CoreProcessRunning = FoundationProcessRunner(),
        operationCoordinator: GameOperationCoordinator = GameOperationCoordinator(),
        onInstalled: (@Sendable (String) async -> Void)? = nil
    ) {
        self.database = database
        self.provider = provider
        self.jobs = jobs
        self.dataDirectory = dataDirectory
        self.fixtureMode = fixtureMode
        self.hpatchzURL = hpatchzURL
        self.processRunner = processRunner
        self.operationCoordinator = operationCoordinator
        self.onInstalled = onInstalled
    }
    func state(installPath: String?) async throws -> GameState {
        try ensureAvailable()
        let configured: String?
        if let requested = installPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty {
            configured = try GameFilesystem.validatedPath(requested)
        } else {
            let saved = try await savedPath()
            if let saved = saved?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty {
                configured = try GameFilesystem.validatedPath(saved)
            } else {
                configured = try GameFilesystem.validatedPath(
                    dataDirectory.appending(path: "Games/Genshin Impact Game").path
                )
            }
        }
        try ensureAvailable()
        try await recoverActivationWithLease(path: configured)
        let detected = configured.flatMap(GameFilesystem.detect)
        let resume = detected == nil
            ? configured.flatMap { installResume(for: URL(filePath: $0)) }
            : nil
        let path = detected?.path.path ?? resume?.destination.path ?? configured ?? ""
        let version = detected?.version ?? resume?.version ?? ""
        let languages = detected.map { GameFilesystem.audioLanguages(at: $0.path) }
            ?? resume.map { GameFilesystem.audioLanguages(at: $0.stage) }
            ?? ["zh-cn"]
        let checkedBuild = try SophonValidation.validate(
            try await provider.build(installedVersion: version, audioLanguages: languages)
        )
        let build = prepareInstalledBuild(
            checkedBuild,
            root: detected?.path ?? resume?.stage,
            installedVersion: version
        )
        let predownload: GameBuild?
        if detected != nil, !version.isEmpty {
            predownload = try? await provider.predownloadBuild(
                installedVersion: version,
                audioLanguages: languages
            )
        } else {
            predownload = nil
        }
        try ensureAvailable()
        let checkedPredownload = predownload.flatMap { try? SophonValidation.validate($0) }
        let status: GameStatus = detected == nil ? (resume != nil ? .damaged : .notInstalled)
            : SophonVersion.compare(version, build.version) >= 0 ? .ready : .updateAvailable
        try ensureAvailable()
        if let detected { try await saveState(path: detected.path.path, version: version, status: status) }
        return GameState(
            installPath: path,
            installedVersion: version,
            availableVersion: build.version,
            status: status,
            updateKind: build.kind,
            downloadBytes: build.downloadSize,
            predownloadVersion: checkedPredownload?.version,
            predownloadFinished: checkedPredownload == nil ? false : try predownloadReady(
                checkedPredownload!, root: detected?.path
            )
        )
    }
    func spaceCheck(path: String, kind: JobKind) async throws -> SpaceCheckResult {
        try ensureAvailable()
        let path = try GameFilesystem.validatedPath(path)
        try await recoverActivationWithLease(path: path)
        let detected = GameFilesystem.detect(at: path)
        guard detected != nil || kind == .install else {
            throw LauncherCoreError(code: "game_not_installed", message: "资源操作需要已安装的游戏客户端")
        }
        let resume = kind == .install && detected == nil ? installResume(for: path) : nil
        let root = try operationRoot(
            path: path,
            kind: kind,
            detected: detected?.path,
            resumeDestination: resume?.destination
        )
        cleanupStaleStaging(destination: root)
        let version = detected?.version ?? resume?.version ?? ""
        let languages = detected.map { GameFilesystem.audioLanguages(at: $0.path) }
            ?? resume.map { GameFilesystem.audioLanguages(at: $0.stage) }
            ?? ["zh-cn"]
        let build: GameBuild
        switch kind {
        case .predownload:
            guard detected != nil else {
                throw LauncherCoreError(code: "game_not_installed", message: "预下载需要已安装的游戏客户端")
            }
            guard let value = try await provider.predownloadBuild(
                installedVersion: version,
                audioLanguages: languages
            ) else { throw LauncherCoreError(code: "predownload_missing", message: "当前没有可用的预下载资源") }
            build = try SophonValidation.validate(value)
        case .verify:
            build = try SophonValidation.validate(
                try await provider.installedBuild(version: version, audioLanguages: languages)
            )
        default:
            build = try SophonValidation.validate(
                try await provider.build(installedVersion: version, audioLanguages: languages)
            )
        }
        try ensureAvailable()
        let prepared = prepareInstalledBuild(
            build,
            root: detected?.path ?? resume?.stage,
            installedVersion: version
        )
        return try spaceResult(build: prepared, kind: kind, root: root, detected: detected?.path)
    }
    func start(kind: JobKind, installPath: String) async throws -> GameJob {
        try ensureAvailable()
        let installPath = try GameFilesystem.validatedPath(installPath)
        let lease = try await operationCoordinator.acquire(.resources)
        do {
            let job = try await startResourceJob(kind: kind, installPath: installPath, lease: lease)
            return job
        } catch {
            await operationCoordinator.release(lease)
            throw error
        }
    }

    private func startResourceJob(
        kind: JobKind,
        installPath: String,
        lease: UUID
    ) async throws -> GameJob {
        try recoverActivation(path: installPath)
        let detected = GameFilesystem.detect(at: installPath)
        guard detected != nil || kind == .install else {
            throw LauncherCoreError(code: "game_not_installed", message: "资源操作需要已安装的游戏客户端")
        }
        let resume = kind == .install && detected == nil
            ? installResume(for: URL(filePath: installPath))
            : nil
        let root = try operationRoot(
            path: installPath,
            kind: kind,
            detected: detected?.path,
            resumeDestination: resume?.destination
        )
        cleanupStaleStaging(destination: root)
        let version = detected?.version ?? resume?.version ?? ""
        let languages = detected.map { GameFilesystem.audioLanguages(at: $0.path) }
            ?? resume.map { GameFilesystem.audioLanguages(at: $0.stage) }
            ?? ["zh-cn"]
        let build: GameBuild
        switch kind {
        case .predownload:
            guard detected != nil else {
                throw LauncherCoreError(code: "game_not_installed", message: "预下载需要已安装的游戏客户端")
            }
            guard let value = try await provider.predownloadBuild(
                installedVersion: version,
                audioLanguages: languages
            ) else { throw LauncherCoreError(code: "predownload_missing", message: "当前没有可用的预下载资源") }
            build = value
        case .verify:
            guard !version.isEmpty else {
                throw LauncherCoreError(code: "game_not_installed", message: "未检测到游戏安装")
            }
            build = try await provider.installedBuild(version: version, audioLanguages: languages)
        default:
            build = try await provider.build(installedVersion: version, audioLanguages: languages)
        }
        try ensureAvailable()
        let checked = try SophonValidation.validate(build)
        let prepared = [.install, .update, .verify].contains(kind)
            ? prepareInstalledBuild(
                checked,
                root: detected?.path ?? resume?.stage,
                installedVersion: version
            )
            : checked
        let space = try spaceResult(build: prepared, kind: kind, root: root, detected: detected?.path)
        guard space.sufficient else {
            throw LauncherCoreError(code: "disk_space_insufficient", message: "磁盘空间不足，请释放空间后重试")
        }
        if kind == .update, SophonVersion.compare(version, prepared.version) >= 0 {
            throw LauncherCoreError(code: "game_already_current", message: "当前游戏版本已是最新")
        }
        let hasWork = !prepared.assets.isEmpty || !prepared.patchAssets.isEmpty
            || !prepared.segments.isEmpty || !prepared.deprecatedFiles.isEmpty
        if kind == .install, resume == nil, version != prepared.version, !hasWork {
            throw LauncherCoreError(code: "game_build_empty", message: "下载服务返回了不完整的空构建")
        }
        if kind == .update, !version.isEmpty, version != prepared.version, !hasWork,
           prepared.repairAssets.isEmpty {
            throw LauncherCoreError(code: "game_build_empty", message: "下载服务返回了不完整的空构建")
        }
        let coordinator = operationCoordinator
        let chunksTotal = Int64(Set(
            prepared.assets.flatMap { $0.requiredChunks ?? $0.chunks }.map(\.name)
                + prepared.patchAssets.map { $0.patch.id }
        ).count)
        let queuedMessage: String = switch kind {
        case .predownload: "预下载任务已排队"
        case .verify: "校验任务已排队"
        case .install: "安装任务已排队"
        case .update: "更新任务已排队"
        }
        return try await jobs.start(
            kind: kind,
            total: prepared.downloadSize,
            message: queuedMessage,
            chunksTotal: chunksTotal
        ) { [self, coordinator, lease] id, control in
            do {
                try await perform(
                    id: id, kind: kind, root: root, detected: detected?.path,
                    resumeStage: resume?.stage, build: prepared, control: control
                )
            } catch {
                await coordinator.release(lease)
                throw error
            }
            await coordinator.release(lease)
        }
    }

    func events(_ id: String, after: Int?) async -> AsyncThrowingStream<GameJob, Error> {
        await jobs.events(id, after: after)
    }

    func control(_ id: String, action: String) async throws -> GameJob {
        try await jobs.control(id, action: action)
    }

    func shutdown() async {
        shuttingDown = true
        await jobs.shutdown()
    }

    func speedLimit() -> Int { speedLimitKB }
    func setSpeedLimit(_ value: Int) throws -> Int {
        guard (0...1_048_576).contains(value) else {
            throw LauncherCoreError(code: "speed_limit_invalid", message: "下载限速设置无效")
        }
        speedLimitKB = value
        return value
    }

    private func ensureAvailable() throws {
        guard !shuttingDown else {
            throw LauncherCoreError(code: "game_resource_unavailable", message: "游戏资源服务正在退出")
        }
    }

    private func resetThrottle() {
        let capacity = Double(max(0, speedLimitKB)) * 1024
        throttleTokens = capacity
        throttleUpdatedAt = Date()
    }

    static func validByteRange(_ value: String?, offset: Int64, expectedSize: Int64) -> Bool {
        let parts = value?.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true) ?? []
        guard parts.count == 2, parts[0].lowercased() == "bytes" else { return false }
        let rangeAndTotal = parts[1].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        let range = rangeAndTotal.first?.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true) ?? []
        guard rangeAndTotal.count == 2, range.count == 2,
              let first = Int64(range[0]), let last = Int64(range[1]),
              let total = Int64(rangeAndTotal[1]) else { return false }
        return first == offset && last >= first && last < expectedSize && total == expectedSize
    }

    func waitForDownloadRetry(_ control: GameJobControl, attempt: Int) async throws {
        try await control.checkpoint()
        let exponent = min(max(attempt - 1, 0), 4)
        try await Task.sleep(for: .milliseconds(min(8_000, 500 * (1 << exponent))))
    }

    func throttle(bytes: Int64, control: GameJobControl) async throws {
        guard bytes > 0, speedLimitKB > 0 else { return }
        let rate = Double(speedLimitKB) * 1024
        let capacity = rate
        var remaining = Double(bytes)
        while remaining > 0 {
            try await control.checkpoint()
            let now = Date()
            let elapsed = max(0, now.timeIntervalSince(throttleUpdatedAt))
            throttleTokens = min(capacity, throttleTokens + elapsed * rate)
            throttleUpdatedAt = now
            let acquired = min(remaining, throttleTokens)
            throttleTokens -= acquired
            remaining -= acquired
            if remaining > 0 {
                let delay = max(0.05, min(1, remaining / rate))
                try await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            }
        }
    }

    private func perform(
        id: String,
        kind: JobKind,
        root: URL,
        detected: URL?,
        resumeStage: URL?,
        build: GameBuild,
        control: GameJobControl
    ) async throws {
        resetThrottle()
        if fixtureMode {
            try await fixtureOperation(id: id, kind: kind, root: root, build: build, control: control)
            return
        }
        switch kind {
        case .predownload:
            guard !build.assets.isEmpty || !build.patchAssets.isEmpty else {
                throw LauncherCoreError(code: "predownload_build_empty", message: "预下载构建不包含可缓存资源")
            }
            guard let detected else {
                throw LauncherCoreError(code: "game_not_installed", message: "预下载需要已安装的游戏客户端")
            }
            let cache = try downloadCache(root: detected, version: build.version)
            try await cacheChunks(id: id, cache: cache, build: build, control: control)
            try GameFilesystem.writePrivate(
                predownloadMarker(build),
                to: cache.appending(path: ".status.json")
            )
        case .verify:
            guard let detected else { throw LauncherCoreError(code: "game_not_installed", message: "未检测到游戏安装") }
            let cache = try downloadCache(root: detected, version: build.version)
            let invalid = try await invalidAssets(build.assets, root: detected, id: id, control: control)
            try await installAssets(invalid, root: detected, id: id, cache: cache, control: control)
            guard GameFilesystem.regularFile(detected.appending(path: "YuanShen.exe")) else {
                throw LauncherCoreError(code: "game_install_incomplete", message: "资源安装完成后仍缺少 YuanShen.exe，未确认完整安装")
            }
            try GameFilesystem.writePrivate(
                Data(build.version.utf8), to: detected.appending(path: ".mhg-version")
            )
            try GameFilesystem.ensureConfiguration(root: detected, version: build.version)
            try writeIntegrity(build, root: detected)
            try writeAssetNames(build, root: detected)
            try await saveState(path: detected.path, version: build.version, status: .ready)
            try? PrivateFilesystem.removeDirectoryIfPresent(cache)
        case .install, .update:
            try await installOrUpdate(
                id: id,
                kind: kind,
                destination: root,
                detected: detected,
                resumeStage: resumeStage,
                build: build,
                control: control
            )
        }
    }

    private func fixtureOperation(
        id: String,
        kind: JobKind,
        root: URL,
        build: GameBuild,
        control: GameJobControl
    ) async throws {
        try await control.checkpoint()
        await jobs.progress(id, completed: build.downloadSize, message: "Fixture 资源检查完成")
        guard kind == .install else { return }
        try PrivateFilesystem.ensureDirectory(root)
        try GameFilesystem.writePrivate(Data(), to: root.appending(path: "YuanShen.exe"))
        try GameFilesystem.ensureConfiguration(root: root, version: build.version)
        try await saveState(path: root.path, version: build.version, status: .ready)
        if let onInstalled { Task { await onInstalled(build.version) } }
    }

    private func installOrUpdate(
        id: String,
        kind: JobKind,
        destination: URL,
        detected: URL?,
        resumeStage: URL?,
        build: GameBuild,
        control: GameJobControl
    ) async throws {
        let parent = destination.deletingLastPathComponent()
        try PrivateFilesystem.ensureDirectory(parent)
        let stage = resumeStage?.standardizedFileURL
            ?? parent.appending(path: ".\(destination.lastPathComponent).mhg-staging-\(id)")
        let backup = parent.appending(path: ".\(destination.lastPathComponent).mhg-backup-\(id)")
        let inPlaceResume = stage == destination.standardizedFileURL
        try PrivateFilesystem.rejectSymbolicLinks(in: stage)
        try PrivateFilesystem.rejectSymbolicLinks(in: backup)
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        if resumeStage == nil { try PrivateFilesystem.removeDirectoryIfPresent(stage) }
        try PrivateFilesystem.removeDirectoryIfPresent(backup)
        do {
            if let resumeStage {
                try PrivateFilesystem.rejectSymbolicLinksRecursively(in: resumeStage)
            } else if let detected {
                try PrivateFilesystem.rejectSymbolicLinksRecursively(in: detected)
                try FileManager.default.copyItem(at: detected, to: stage)
            } else {
                try PrivateFilesystem.ensureDirectory(stage)
            }
            try writeOwnership(id: id, kind: kind, destination: destination, version: build.version, stage: stage)
            let cache = try downloadCache(root: destination, version: build.version)
            var performed = false
            var patchFailure: Error?
            if !build.patchAssets.isEmpty || !build.deprecatedFiles.isEmpty {
                performed = true
                do {
                    try await applyPatches(build.patchAssets, root: stage, cache: cache, id: id, control: control)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard !build.repairAssets.isEmpty, !isFatalPatchFailure(error) else { throw error }
                    patchFailure = error
                }
                for name in build.deprecatedFiles {
                    guard !SophonValidation.isLauncherManagedPath(name) else { continue }
                    let target = try GameFilesystem.safeTarget(root: stage, relativePath: name)
                    guard GameFilesystem.regularFile(target) else { continue }
                    try PrivateFilesystem.removeRegularFileIfPresent(target)
                }
            }
            if !build.assets.isEmpty {
                performed = true
                try await installAssets(
                    build.assets,
                    root: stage,
                    id: id,
                    baseAssets: build.baseAssets,
                    cache: cache,
                    control: control
                )
            } else if !build.segments.isEmpty {
                performed = true
                try await GameArchive.install(
                    segments: build.segments,
                    cache: cache,
                    destination: stage,
                    checkpoint: { try await control.checkpoint() },
                    throttle: { bytes in try await self.throttle(bytes: bytes, control: control) },
                    progress: { bytes in
                        await self.jobs.addProgress(id, bytes: bytes, message: "正在下载游戏安装包")
                    }
                )
            } else if !performed, kind != .verify,
                      !(kind == .install && !build.repairAssets.isEmpty) {
                throw LauncherCoreError(code: "game_build_empty", message: "下载服务返回了不完整的空构建")
            }
            let canonical = build.repairAssets.isEmpty ? build.assets : build.repairAssets
            if !canonical.isEmpty {
                let invalid = try await invalidAssets(canonical, root: stage, id: id, control: control)
                if !invalid.isEmpty {
                    try await installAssets(
                        invalid,
                        root: stage,
                        id: id,
                        cache: cache,
                        control: control
                    )
                }
            } else if let patchFailure {
                throw patchFailure
            }
            if !build.segments.isEmpty {
                try GameArchive.verifyManifest(in: stage)
            }
            guard GameFilesystem.regularFile(stage.appending(path: "YuanShen.exe")) else {
                throw LauncherCoreError(code: "game_install_incomplete", message: "资源安装完成后仍缺少 YuanShen.exe，未激活不完整目录")
            }
            try GameFilesystem.writePrivate(
                Data(build.version.utf8), to: stage.appending(path: ".mhg-version")
            )
            try GameFilesystem.ensureConfiguration(root: stage, version: build.version)
            try writeIntegrity(build, root: stage)
            try writeAssetNames(build, root: stage)
            if !inPlaceResume {
                try activate(stage: stage, destination: destination, backup: backup)
            }
            clearStagingMarkers(in: destination)
            try await saveState(path: destination.path, version: build.version, status: .ready)
            for scope in downloadCacheScopes(root: destination) {
                try? PrivateFilesystem.removeDirectoryIfPresent(scope)
            }
            if kind == .install || kind == .update, let onInstalled {
                Task { await onInstalled(build.version) }
            }
        } catch {
            if kind != .install { try? PrivateFilesystem.removeDirectoryIfPresent(stage) }
            throw error
        }
    }

    private func isFatalPatchFailure(_ error: Error) -> Bool {
        if (error as? LauncherCoreError)?.code == "sophon_storage_failed" { return true }
        guard let error = error as? POSIXError else { return false }
        return [.EACCES, .EDQUOT, .ENOSPC, .EROFS].contains(error.code)
    }

    private func clearStagingMarkers(in root: URL) {
        for name in [".mhg-staging.json", ".mhg-staging-version"] {
            try? PrivateFilesystem.removeRegularFileIfPresent(root.appending(path: name))
        }
    }

    private func installAssets(
        _ assets: [GameAsset],
        root: URL,
        id: String,
        baseAssets: [GameAsset] = [],
        cache: URL? = nil,
        control: GameJobControl
    ) async throws {
        let baseByName = Dictionary(
            baseAssets.map { (SophonValidation.canonicalPath($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var completed: Int64 = 0
        for asset in assets {
            try await control.checkpoint()
            let target = try GameFilesystem.safeTarget(root: root, relativePath: asset.name)
            if GameFilesystem.regularFile(target),
               (try await FileDigest.md5(target)) == asset.md5.lowercased() {
                let bytes = (asset.requiredChunks ?? asset.chunks).reduce(into: Int64(0)) {
                    $0 = $0 > Int64.max - $1.size ? Int64.max : $0 + $1.size
                }
                completed = completed > Int64.max - bytes ? Int64.max : completed + bytes
                await jobs.progress(id, completed: completed, message: "已校验 \(asset.name)")
                await jobs.markChunks(
                    id,
                    names: (asset.requiredChunks ?? asset.chunks).map(\.name)
                )
                continue
            }
            let base = baseByName[SophonValidation.canonicalPath(asset.name)]
            let before = completed
            do {
                try await assemble(
                    asset: asset,
                    base: base,
                    target: target,
                    cache: cache,
                    id: id,
                    completed: &completed,
                    control: control
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard base != nil, asset.requiredChunks != nil else { throw error }
                completed = before
                await jobs.progress(id, completed: completed, message: "正在完整下载 \(asset.name)")
                try await assemble(
                    asset: asset,
                    base: nil,
                    target: target,
                    cache: cache,
                    id: id,
                    completed: &completed,
                    control: control
                )
            }
        }
    }

    private func assemble(
        asset: GameAsset,
        base: GameAsset?,
        target: URL,
        cache: URL?,
        id: String,
        completed: inout Int64,
        control: GameJobControl
    ) async throws {
        let temporary = URL(filePath: target.path + ".\(id).mhg-installing")
        try GameFilesystem.ensureParent(of: target)
        try PrivateFilesystem.rejectSymbolicLinks(in: temporary)
        guard FileManager.default.createFile(
            atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ) else {
            throw LauncherCoreError(code: "sophon_storage_failed", message: "无法创建游戏资源临时文件")
        }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        do {
            try output.truncate(atOffset: UInt64(asset.size))
            let oldChunks = Dictionary(
                base?.chunks.map { ($0.decompressedMD5.lowercased(), $0) } ?? [],
                uniquingKeysWith: { first, _ in first }
            )
            let required = asset.requiredChunks ?? asset.chunks
            let requiredNames = Set(required.map { $0.decompressedMD5.lowercased() })
            let canReuse = asset.requiredChunks != nil && base != nil && GameFilesystem.regularFile(target)
                && asset.chunks.allSatisfy { chunk in
                    requiredNames.contains(chunk.decompressedMD5.lowercased())
                        || oldChunks[chunk.decompressedMD5.lowercased()]?.decompressedSize == chunk.decompressedSize
                }
            for chunk in asset.chunks {
                try await control.checkpoint()
                if !canReuse || requiredNames.contains(chunk.decompressedMD5.lowercased()) {
                    let compressed = try await download(chunk, cache: cache, id: id, control: control)
                    let decoded = try Zstandard.decompress(compressed, maximumBytes: Int(chunk.decompressedSize))
                    guard decoded.count == chunk.decompressedSize,
                          CoreHash.md5(decoded) == chunk.decompressedMD5.lowercased() else {
                        throw LauncherCoreError(code: "sophon_chunk_content_invalid", message: "\(chunk.name) 内容校验失败")
                    }
                    try output.seek(toOffset: UInt64(chunk.offset))
                    try output.write(contentsOf: decoded)
                    completed = completed > Int64.max - chunk.size ? Int64.max : completed + chunk.size
                } else {
                    guard let source = oldChunks[chunk.decompressedMD5.lowercased()],
                          source.decompressedSize == chunk.decompressedSize else {
                        throw LauncherCoreError(code: "sophon_diff_source_missing", message: "\(asset.name) 缺少可复用分块")
                    }
                    try copyRange(
                        source: target,
                        inputOffset: source.offset,
                        destination: output,
                        outputOffset: chunk.offset,
                        count: chunk.decompressedSize
                    )
                }
                await jobs.progress(
                    id,
                    completed: completed,
                    message: "正在安装 \(asset.name)",
                    chunk: ChunkProgress(name: chunk.name, bytesDone: chunk.size, total: chunk.size)
                )
            }
            try output.synchronize()
            guard try await FileDigest.md5(temporary) == asset.md5.lowercased() else {
                throw LauncherCoreError(code: "sophon_asset_invalid", message: "\(asset.name) 文件校验失败")
            }
            if FileManager.default.fileExists(atPath: target.path) {
                guard GameFilesystem.regularFile(target) else {
                    throw LauncherCoreError(code: "sophon_target_invalid", message: "\(asset.name) 目标路径不是普通文件")
                }
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: target)
            }
            try PrivateFilesystem.setPrivateFilePermissions(target)
        } catch {
            try? PrivateFilesystem.removeRegularFileIfPresent(temporary)
            throw error
        }
    }

    private func applyPatches(
        _ assets: [GamePatchAsset],
        root: URL,
        cache: URL?,
        id: String,
        control: GameJobControl
    ) async throws {
        guard !assets.isEmpty else { return }
        guard GameFilesystem.regularFile(hpatchzURL) else {
            throw LauncherCoreError(code: "hpatchz_unavailable", message: "差分补丁工具尚未安装")
        }
        let cache = cache ?? dataDirectory.appending(path: "GameDownloads/patches")
        try PrivateFilesystem.ensureDirectory(cache)
        var sources: [String: URL] = [:]
        var completed: Int64 = 0
        let patches = assets.reduce(into: [String: SophonPatch]()) { $0[$1.patch.id] = $1.patch }
        for patch in patches.values {
            try await control.checkpoint()
            let source = try GameFilesystem.safeTarget(root: cache, relativePath: patch.id)
            if !GameFilesystem.regularFile(source)
                || (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) != Int(patch.fileSize)
                || (try? CoreHash.xxHash64(file: source)) != patch.id.split(separator: "_").first.map(String.init)?.lowercased() {
                guard patch.fileSize <= 2 * 1024 * 1024 * 1024 else {
                    throw LauncherCoreError(code: "sophon_patch_too_large", message: "增量补丁大小超过限制")
                }
                try await downloadPatch(patch, to: source, control: control)
            }
            sources[patch.id] = source
            completed = completed > Int64.max - patch.fileSize ? Int64.max : completed + patch.fileSize
            await jobs.progress(
                id,
                completed: completed,
                message: "已下载增量补丁",
                chunk: ChunkProgress(name: patch.id, bytesDone: patch.fileSize, total: patch.fileSize)
            )
        }
        for asset in assets {
            try await control.checkpoint()
            guard let source = sources[asset.patch.id] else {
                throw LauncherCoreError(code: "sophon_patch_missing", message: "增量补丁缓存不存在")
            }
            try await applyPatch(asset, source: source, root: root)
            await jobs.progress(id, completed: completed, message: "正在应用 \(asset.name)")
        }
    }

    private func applyPatch(_ asset: GamePatchAsset, source: URL, root: URL) async throws {
        let target = try GameFilesystem.safeTarget(root: root, relativePath: asset.name)
        try GameFilesystem.ensureParent(of: target)
        let token = UUID().uuidString
        let segment = root.appending(path: ".mhg-patch-segment-\(token)")
        let output = root.appending(path: ".mhg-patch-output-\(token)")
        try PrivateFilesystem.rejectSymbolicLinks(in: segment)
        try PrivateFilesystem.rejectSymbolicLinks(in: output)
        defer {
            try? PrivateFilesystem.removeRegularFileIfPresent(segment)
            try? PrivateFilesystem.removeRegularFileIfPresent(output)
        }
        do {
            try copyRange(
                source: source, destination: segment,
                offset: asset.patch.start, count: asset.patch.length
            )
        } catch {
            throw LauncherCoreError(code: "sophon_patch_range_invalid", message: "\(asset.name) 增量补丁范围无效")
        }
        let prepared: URL
        if asset.patch.originalName.isEmpty {
            prepared = segment
        } else {
            let original = try GameFilesystem.safeTarget(root: root, relativePath: asset.patch.originalName)
            guard GameFilesystem.regularFile(original) else {
                throw LauncherCoreError(code: "sophon_patch_source_missing", message: "\(asset.patch.originalName) 缺少原始文件")
            }
            let status = try await processRunner.run(CoreProcessRequest(
                executable: hpatchzURL,
                arguments: [original.path, segment.path, output.path],
                workingDirectory: root,
                environment: CoreProcessEnvironment.sanitizedCurrentProcess(),
                logURL: nil
            ))
            guard status == 0, GameFilesystem.regularFile(output) else {
                throw LauncherCoreError(code: "sophon_patch_apply_failed", message: "\(asset.name) 增量补丁应用失败")
            }
            prepared = output
        }
        let values = try prepared.resourceValues(forKeys: [.fileSizeKey])
        guard values.fileSize == Int(asset.size), try await FileDigest.md5(prepared) == asset.md5.lowercased() else {
            throw LauncherCoreError(code: "sophon_patch_result_invalid", message: "\(asset.name) 增量更新校验失败")
        }
        if FileManager.default.fileExists(atPath: target.path) {
            guard GameFilesystem.regularFile(target) else {
                throw LauncherCoreError(code: "sophon_target_invalid", message: "\(asset.name) 目标路径不是普通文件")
            }
            _ = try FileManager.default.replaceItemAt(target, withItemAt: prepared)
        } else {
            try FileManager.default.moveItem(at: prepared, to: target)
        }
        try PrivateFilesystem.setPrivateFilePermissions(target)
    }

    private func copyRange(source: URL, destination: URL, offset: Int64, count: Int64) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        guard FileManager.default.createFile(
            atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ) else {
            throw LauncherCoreError(code: "sophon_storage_failed", message: "无法创建补丁临时文件")
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try input.seek(toOffset: UInt64(offset))
        var remaining = count
        while remaining > 0 {
            let amount = Int(min(remaining, 1024 * 1024))
            guard let data = try input.read(upToCount: amount), data.count == amount else {
                throw LauncherCoreError(code: "sophon_patch_range_invalid", message: "增量补丁范围无效")
            }
            try output.write(contentsOf: data)
            remaining -= Int64(amount)
        }
        try output.synchronize()
    }

    private func copyRange(
        source: URL,
        inputOffset: Int64,
        destination: FileHandle,
        outputOffset: Int64,
        count: Int64
    ) throws {
        guard inputOffset >= 0, outputOffset >= 0, count >= 0 else {
            throw LauncherCoreError(code: "sophon_diff_source_missing", message: "可复用分块范围无效")
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try input.seek(toOffset: UInt64(inputOffset))
        try destination.seek(toOffset: UInt64(outputOffset))
        var remaining = count
        while remaining > 0 {
            let amount = Int(min(remaining, 1024 * 1024))
            guard let data = try input.read(upToCount: amount), data.count == amount else {
                throw LauncherCoreError(code: "sophon_diff_source_missing", message: "可复用分块内容不完整")
            }
            try destination.write(contentsOf: data)
            remaining -= Int64(amount)
        }
    }

    private func cacheChunks(
        id: String,
        cache: URL,
        build: GameBuild,
        control: GameJobControl
    ) async throws {
        var completed: Int64 = 0
        if !build.patchAssets.isEmpty {
            let patches = Dictionary(
                build.patchAssets.map { ($0.patch.id.lowercased(), $0.patch) },
                uniquingKeysWith: { first, _ in first }
            )
            for patch in patches.values {
                try await control.checkpoint()
                let target = try GameFilesystem.safeTarget(root: cache, relativePath: patch.id)
                if !GameFilesystem.regularFile(target)
                    || (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) != Int(patch.fileSize)
                    || (try? CoreHash.xxHash64(file: target)) != patch.id.split(separator: "_", maxSplits: 1).first.map(String.init)?.lowercased() {
                    try await downloadPatch(patch, to: target, control: control)
                }
                completed = min(Int64.max, completed + patch.fileSize)
                await jobs.progress(
                    id,
                    completed: completed,
                    message: "正在预下载增量补丁",
                    chunk: ChunkProgress(name: patch.id, bytesDone: patch.fileSize, total: patch.fileSize)
                )
            }
            return
        }
        let chunks = Dictionary(
            build.assets.flatMap { $0.requiredChunks ?? $0.chunks }
                .map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for chunk in chunks.values {
            try await control.checkpoint()
            let target = try GameFilesystem.safeTarget(root: cache, relativePath: chunk.name)
            if GameFilesystem.regularFile(target), (try? CoreHash.xxHash64(file: target)) == chunk.name.split(separator: "_").first.map(String.init)?.lowercased() {
                completed = completed > Int64.max - chunk.size ? Int64.max : completed + chunk.size
            } else {
                let data = try await download(chunk, cache: cache, id: id, control: control)
                try GameFilesystem.writePrivate(data, to: target)
                completed = completed > Int64.max - chunk.size ? Int64.max : completed + chunk.size
            }
            await jobs.progress(
                id,
                completed: completed,
                message: "正在预下载游戏资源",
                chunk: ChunkProgress(name: chunk.name, bytesDone: chunk.size, total: chunk.size)
            )
        }
    }

    private func invalidAssets(
        _ assets: [GameAsset],
        root: URL,
        id: String,
        control: GameJobControl
    ) async throws -> [GameAsset] {
        var invalid: [GameAsset] = []
        var completed: Int64 = 0
        let total = assets.reduce(into: Int64(0)) { result, asset in
            result = result > Int64.max - asset.size ? Int64.max : result + asset.size
        }
        for asset in assets {
            try await control.checkpoint()
            let target = try GameFilesystem.safeTarget(root: root, relativePath: asset.name)
            let digest = GameFilesystem.regularFile(target) ? try await FileDigest.md5(target) : ""
            if digest != asset.md5.lowercased() { invalid.append(asset) }
            completed = min(Int64.max, completed + min(Int64.max - completed, asset.size))
            await jobs.progress(id, completed: completed, total: total, message: "正在校验 \(asset.name)")
        }
        return invalid
    }

    private func activate(stage: URL, destination: URL, backup: URL) throws {
        try GameActivation.activate(stage: stage, destination: destination, backup: backup)
    }

    private func recoverActivation(path: String?) throws {
        guard let path = path?.nonempty else { return }
        let requested = URL(filePath: path).standardizedFileURL
        try GameActivation.recover(destination: requested)
        try GameActivation.recover(destination: requested.appending(path: "Genshin Impact Game"))
    }

    private func recoverActivationWithLease(path: String?) async throws {
        let lease = try await operationCoordinator.acquire(.resources)
        do {
            try recoverActivation(path: path)
            await operationCoordinator.release(lease)
        } catch {
            await operationCoordinator.release(lease)
            throw error
        }
    }

    private func writeOwnership(
        id: String,
        kind: JobKind,
        destination: URL,
        version: String,
        stage: URL
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schema": 1, "owner": id, "pid": ProcessInfo.processInfo.processIdentifier,
            "kind": kind.rawValue, "destination": destination.path, "version": version
        ], options: [.sortedKeys])
        try GameFilesystem.writePrivate(data, to: stage.appending(path: ".mhg-staging.json"))
        try GameFilesystem.writePrivate(
            Data(version.utf8),
            to: stage.appending(path: ".mhg-staging-version")
        )
    }

    private func cleanupStaleStaging(destination: URL) {
        let parent = destination.deletingLastPathComponent()
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: parent)) != nil,
              let enumerator = FileManager.default.enumerator(
                  at: parent,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: [.skipsSubdirectoryDescendants]
              ) else { return }
        let prefixes = [
            ".\(destination.lastPathComponent).mhg-staging-",
            "\(destination.lastPathComponent).mhg-staging-"
        ]
        var scanned = 0
        while let entry = enumerator.nextObject() as? URL {
            scanned += 1
            guard scanned <= 1_024 else { return }
            guard let prefix = prefixes.first(where: { entry.lastPathComponent.hasPrefix($0) }) else {
                continue
            }
            let suffixOwner = String(entry.lastPathComponent.dropFirst(prefix.count))
            guard let values = try? entry.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ), values.isDirectory == true, values.isSymbolicLink != true,
            (try? PrivateFilesystem.rejectSymbolicLinksRecursively(in: entry)) != nil else {
                continue
            }
            let marker = entry.appending(path: ".mhg-staging.json")
            guard GameFilesystem.regularFile(marker),
                  let markerValues = try? marker.resourceValues(forKeys: [.fileSizeKey]),
                  (markerValues.fileSize ?? 0) <= 16 * 1024,
                  let data = try? Data(contentsOf: marker),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let schema = object["schema"] as? NSNumber, schema.intValue == 1,
                  let owner = object["owner"] as? String, UUID(uuidString: owner) != nil,
                  owner == suffixOwner,
                  let pidValue = object["pid"] as? NSNumber,
                  pidValue.int64Value > 0, pidValue.int64Value <= Int64(Int32.max),
                  let kind = object["kind"] as? String, kind == JobKind.update.rawValue,
                  let recordedDestination = object["destination"] as? String,
                  URL(filePath: recordedDestination).standardizedFileURL
                      == destination.standardizedFileURL,
                  let version = object["version"] as? String,
                  SophonValidation.isIdentifier(version),
                  !processAlive(Int32(pidValue.int32Value)) else {
                continue
            }
            try? PrivateFilesystem.removeDirectoryIfPresent(entry)
        }
    }

}
