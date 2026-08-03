import Foundation
import GRDB

actor CoreGameService {
    private let database: CoreDatabase
    private let provider: any GameProvider
    private let jobs: GameJobCoordinator
    private let dataDirectory: URL
    private let fixtureMode: Bool
    private let hpatchzURL: URL
    private let processRunner: any CoreProcessRunning
    private var speedLimitKB = 0

    init(
        database: CoreDatabase,
        provider: any GameProvider,
        jobs: GameJobCoordinator,
        dataDirectory: URL,
        fixtureMode: Bool,
        hpatchzURL: URL,
        processRunner: any CoreProcessRunning = FoundationProcessRunner()
    ) {
        self.database = database
        self.provider = provider
        self.jobs = jobs
        self.dataDirectory = dataDirectory
        self.fixtureMode = fixtureMode
        self.hpatchzURL = hpatchzURL
        self.processRunner = processRunner
    }

    func state(installPath: String?) async throws -> GameState {
        let configured: String?
        if let requested = installPath?.nonempty { configured = requested }
        else { configured = try await savedPath() }
        let detected = configured.flatMap(GameFilesystem.detect)
        let path = detected?.path.path ?? configured ?? ""
        let version = detected?.version ?? ""
        let languages = detected.map { GameFilesystem.audioLanguages(at: $0.path) } ?? ["zh-cn"]
        let build = try await provider.build(installedVersion: version, audioLanguages: languages)
        let predownload = try await provider.predownloadBuild(
            installedVersion: version,
            audioLanguages: languages
        )
        let status: GameStatus = detected == nil ? .notInstalled
            : version == build.version ? .ready : .updateAvailable
        if let detected { try await saveState(path: detected.path.path, version: version, status: status) }
        return GameState(
            installPath: path,
            installedVersion: version,
            availableVersion: build.version,
            status: status,
            updateKind: build.kind,
            downloadBytes: build.downloadSize,
            predownloadVersion: predownload?.version,
            predownloadFinished: predownload == nil ? false : try predownloadReady(predownload!)
        )
    }

    func spaceCheck(path: String, kind: JobKind) async throws -> SpaceCheckResult {
        let root = URL(filePath: path).standardizedFileURL
        let detected = GameFilesystem.detect(at: path)
        let version = detected?.version ?? ""
        let languages = detected.map { GameFilesystem.audioLanguages(at: $0.path) } ?? ["zh-cn"]
        let build: GameBuild
        switch kind {
        case .predownload:
            guard let value = try await provider.predownloadBuild(
                installedVersion: version,
                audioLanguages: languages
            ) else { throw LauncherCoreError(code: "predownload_missing", message: "当前没有可用的预下载资源") }
            build = value
        case .verify:
            build = try await provider.installedBuild(version: version, audioLanguages: languages)
        default:
            build = try await provider.build(installedVersion: version, audioLanguages: languages)
        }
        let required = kind == .predownload ? build.downloadSize : max(build.downloadSize, outputSize(build))
        let probe = existingAncestor(root)
        let values = try probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return SpaceCheckResult(available: available, required: required, sufficient: available >= required)
    }

    func start(kind: JobKind, installPath: String) async throws -> GameJob {
        let root = URL(filePath: installPath).standardizedFileURL
        let detected = GameFilesystem.detect(at: installPath)
        let version = detected?.version ?? ""
        let languages = detected.map { GameFilesystem.audioLanguages(at: $0.path) } ?? ["zh-cn"]
        let build: GameBuild
        switch kind {
        case .predownload:
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
        let checked = try SophonValidation.validate(build)
        return try await jobs.start(kind: kind, total: checked.downloadSize) { [self] id, control in
            try await perform(id: id, kind: kind, root: root, detected: detected?.path, build: checked, control: control)
        }
    }

    func events(_ id: String, after: Int?) async -> AsyncThrowingStream<GameJob, Error> {
        await jobs.events(id, after: after)
    }

    func control(_ id: String, action: String) async throws -> GameJob {
        try await jobs.control(id, action: action)
    }

    func shutdown() async {
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

    private func perform(
        id: String,
        kind: JobKind,
        root: URL,
        detected: URL?,
        build: GameBuild,
        control: GameJobControl
    ) async throws {
        if fixtureMode {
            try await fixtureOperation(id: id, kind: kind, root: root, build: build, control: control)
            return
        }
        switch kind {
        case .predownload:
            try await cacheChunks(id: id, build: build, control: control)
            try predownloadMarker(build).write(to: predownloadMarkerURL, atomically: true, encoding: .utf8)
            try PrivateFilesystem.setPrivateFilePermissions(predownloadMarkerURL)
        case .verify:
            guard let detected else { throw LauncherCoreError(code: "game_not_installed", message: "未检测到游戏安装") }
            let invalid = try await invalidAssets(build.assets, root: detected, id: id, control: control)
            try await installAssets(invalid, root: detected, id: id, control: control)
            try writeIntegrity(build, root: detected)
        case .install, .update:
            try await installOrUpdate(id: id, kind: kind, destination: root, detected: detected, build: build, control: control)
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
        try GameFilesystem.writePrivate(Data("game_version=\(build.version)\n".utf8), to: root.appending(path: "config.ini"))
        try await saveState(path: root.path, version: build.version, status: .ready)
    }

    private func installOrUpdate(
        id: String,
        kind: JobKind,
        destination: URL,
        detected: URL?,
        build: GameBuild,
        control: GameJobControl
    ) async throws {
        let parent = destination.deletingLastPathComponent()
        try PrivateFilesystem.ensureDirectory(parent)
        let stage = parent.appending(path: ".\(destination.lastPathComponent).mhg-staging-\(id)")
        let backup = parent.appending(path: ".\(destination.lastPathComponent).mhg-backup-\(id)")
        try? FileManager.default.removeItem(at: stage)
        try? FileManager.default.removeItem(at: backup)
        do {
            if kind == .update, let detected {
                try FileManager.default.copyItem(at: detected, to: stage)
            } else {
                try PrivateFilesystem.ensureDirectory(stage)
            }
            try writeOwnership(id: id, kind: kind, destination: destination, version: build.version, stage: stage)
            guard build.segments.isEmpty else {
                throw LauncherCoreError(code: "package_build_unsupported", message: "当前构建缺少 Sophon 资源清单")
            }
            try await installAssets(build.assets, root: stage, id: id, control: control)
            try await applyPatches(build.patchAssets, root: stage, id: id, control: control)
            for name in build.deprecatedFiles {
                guard URL(filePath: name).lastPathComponent.lowercased() != "mhypbase.dll" else { continue }
                try? FileManager.default.removeItem(at: GameFilesystem.safeTarget(root: stage, relativePath: name))
            }
            try GameFilesystem.writePrivate(Data("game_version=\(build.version)\n".utf8), to: stage.appending(path: "config.ini"))
            try writeIntegrity(build, root: stage)
            try activate(stage: stage, destination: destination, backup: backup)
            try await saveState(path: destination.path, version: build.version, status: .ready)
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }

    private func installAssets(
        _ assets: [GameAsset],
        root: URL,
        id: String,
        control: GameJobControl
    ) async throws {
        var completed: Int64 = 0
        for asset in assets {
            try await control.checkpoint()
            let target = try GameFilesystem.safeTarget(root: root, relativePath: asset.name)
            if GameFilesystem.regularFile(target),
               (try await FileDigest.md5(target)) == asset.md5.lowercased() {
                completed += (asset.requiredChunks ?? asset.chunks).reduce(0) { $0 + $1.size }
                await jobs.progress(id, completed: completed, message: "已校验 \(asset.name)")
                continue
            }
            try await assemble(asset: asset, target: target, id: id, completed: &completed, control: control)
        }
    }

    private func assemble(
        asset: GameAsset,
        target: URL,
        id: String,
        completed: inout Int64,
        control: GameJobControl
    ) async throws {
        let temporary = URL(filePath: target.path + ".\(id).mhg-installing")
        try GameFilesystem.ensureParent(of: target)
        FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        do {
            try output.truncate(atOffset: UInt64(asset.size))
            for chunk in asset.chunks {
                try await control.checkpoint()
                let compressed = try await download(chunk, id: id, control: control)
                let decoded = try Zstandard.decompress(compressed, maximumBytes: Int(chunk.decompressedSize))
                guard decoded.count == chunk.decompressedSize,
                      CoreHash.md5(decoded) == chunk.decompressedMD5.lowercased() else {
                    throw LauncherCoreError(code: "sophon_chunk_content_invalid", message: "\(chunk.name) 内容校验失败")
                }
                try output.seek(toOffset: UInt64(chunk.offset))
                try output.write(contentsOf: decoded)
                completed += chunk.size
                await jobs.progress(id, completed: completed, message: "正在安装 \(asset.name)")
            }
            try output.synchronize()
            guard try await FileDigest.md5(temporary) == asset.md5.lowercased() else {
                throw LauncherCoreError(code: "sophon_asset_invalid", message: "\(asset.name) 文件校验失败")
            }
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: target)
            }
            try PrivateFilesystem.setPrivateFilePermissions(target)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func download(_ chunk: SophonChunk, id: String, control: GameJobControl) async throws -> Data {
        guard chunk.size > 0, chunk.size <= 256 * 1024 * 1024 else {
            throw LauncherCoreError(code: "sophon_chunk_invalid", message: "Sophon 分块大小无效")
        }
        let policy = HTTPSHostPolicy(exactHosts: [chunk.url.host?.lowercased() ?? ""], suffixes: ["mihoyo.com"])
        let transport = URLSessionHTTPTransport()
        let payload = try await transport.send(
            URLRequest(url: chunk.url, timeoutInterval: 60),
            policy: policy,
            maximumBytes: Int(chunk.size)
        )
        try await control.checkpoint()
        guard (200..<300).contains(payload.statusCode), payload.data.count == chunk.size,
              CoreHash.xxHash64(payload.data) == chunk.name.split(separator: "_", maxSplits: 1).first.map(String.init)?.lowercased() else {
            throw LauncherCoreError(code: "sophon_chunk_invalid", message: "\(chunk.name) 分块校验失败")
        }
        return payload.data
    }

    private func applyPatches(
        _ assets: [GamePatchAsset],
        root: URL,
        id: String,
        control: GameJobControl
    ) async throws {
        guard !assets.isEmpty else { return }
        guard GameFilesystem.regularFile(hpatchzURL) else {
            throw LauncherCoreError(code: "hpatchz_unavailable", message: "差分补丁工具尚未安装")
        }
        let cache = dataDirectory.appending(path: "GameDownloads/patches")
        try PrivateFilesystem.ensureDirectory(cache)
        var sources: [String: URL] = [:]
        let patches = assets.reduce(into: [String: SophonPatch]()) { $0[$1.patch.id] = $1.patch }
        for patch in patches.values {
            try await control.checkpoint()
            let source = cache.appending(path: patch.id)
            if !GameFilesystem.regularFile(source)
                || (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) != Int(patch.fileSize)
                || (try? CoreHash.xxHash64(file: source)) != patch.id.split(separator: "_").first.map(String.init)?.lowercased() {
                guard patch.fileSize <= 2 * 1024 * 1024 * 1024 else {
                    throw LauncherCoreError(code: "sophon_patch_too_large", message: "增量补丁大小超过限制")
                }
                let transport = URLSessionHTTPTransport()
                let payload = try await transport.send(
                    URLRequest(url: patch.url, timeoutInterval: 120),
                    policy: HTTPSHostPolicy(
                        exactHosts: [patch.url.host?.lowercased() ?? ""],
                        suffixes: ["mihoyo.com"]
                    ),
                    maximumBytes: Int(patch.fileSize)
                )
                guard (200..<300).contains(payload.statusCode), Int64(payload.data.count) == patch.fileSize,
                      CoreHash.xxHash64(payload.data) == patch.id.split(separator: "_").first.map(String.init)?.lowercased() else {
                    throw LauncherCoreError(code: "sophon_patch_invalid", message: "增量补丁校验失败")
                }
                try GameFilesystem.writePrivate(payload.data, to: source)
            }
            sources[patch.id] = source
            await jobs.progress(id, completed: patch.fileSize, message: "已下载增量补丁")
        }
        for asset in assets {
            try await control.checkpoint()
            guard let source = sources[asset.patch.id] else {
                throw LauncherCoreError(code: "sophon_patch_missing", message: "增量补丁缓存不存在")
            }
            try await applyPatch(asset, source: source, root: root)
            await jobs.progress(id, completed: asset.patch.fileSize, message: "正在应用 \(asset.name)")
        }
    }

    private func applyPatch(_ asset: GamePatchAsset, source: URL, root: URL) async throws {
        let target = try GameFilesystem.safeTarget(root: root, relativePath: asset.name)
        try GameFilesystem.ensureParent(of: target)
        let token = UUID().uuidString
        let segment = root.appending(path: ".mhg-patch-segment-\(token)")
        let output = root.appending(path: ".mhg-patch-output-\(token)")
        defer {
            try? FileManager.default.removeItem(at: segment)
            try? FileManager.default.removeItem(at: output)
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
                environment: ProcessInfo.processInfo.environment,
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
            _ = try FileManager.default.replaceItemAt(target, withItemAt: prepared)
        } else {
            try FileManager.default.moveItem(at: prepared, to: target)
        }
        try PrivateFilesystem.setPrivateFilePermissions(target)
    }

    private func copyRange(source: URL, destination: URL, offset: Int64, count: Int64) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600])
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

    private func cacheChunks(id: String, build: GameBuild, control: GameJobControl) async throws {
        let root = dataDirectory.appending(path: "GameDownloads/predownload/\(build.version)")
        try PrivateFilesystem.ensureDirectory(root)
        var completed: Int64 = 0
        for chunk in build.assets.flatMap({ $0.requiredChunks ?? $0.chunks }) {
            let target = root.appending(path: chunk.name)
            if GameFilesystem.regularFile(target), (try? CoreHash.xxHash64(file: target)) == chunk.name.split(separator: "_").first.map(String.init)?.lowercased() {
                completed += chunk.size
            } else {
                let data = try await download(chunk, id: id, control: control)
                try GameFilesystem.writePrivate(data, to: target)
                completed += chunk.size
            }
            await jobs.progress(id, completed: completed, message: "正在预下载游戏资源")
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
        for asset in assets {
            try await control.checkpoint()
            let target = try GameFilesystem.safeTarget(root: root, relativePath: asset.name)
            let digest = GameFilesystem.regularFile(target) ? try await FileDigest.md5(target) : ""
            if digest != asset.md5.lowercased() { invalid.append(asset) }
            completed += asset.size
            await jobs.progress(id, completed: completed, total: assets.reduce(0) { $0 + $1.size }, message: "正在校验 \(asset.name)")
        }
        return invalid
    }

    private func activate(stage: URL, destination: URL, backup: URL) throws {
        let manager = FileManager.default
        let hadDestination = manager.fileExists(atPath: destination.path)
        if hadDestination { try manager.moveItem(at: destination, to: backup) }
        do {
            try manager.moveItem(at: stage, to: destination)
            if hadDestination { try? manager.removeItem(at: backup) }
        } catch {
            try? manager.removeItem(at: destination)
            if hadDestination { try? manager.moveItem(at: backup, to: destination) }
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
    }

    private func writeIntegrity(_ build: GameBuild, root: URL) throws {
        var assets: [String: [String: Any]] = [:]
        for asset in build.assets + build.patchAssets.map({ GameAsset(name: $0.name, size: $0.size, md5: $0.md5, chunks: [], requiredChunks: nil) }) {
            guard URL(filePath: asset.name).lastPathComponent.lowercased() != "mhypbase.dll" else { continue }
            let url = try GameFilesystem.safeTarget(root: root, relativePath: asset.name)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            assets[asset.name.replacingOccurrences(of: "\\", with: "/")] = [
                "md5": asset.md5.lowercased(), "size": values.fileSize ?? 0,
                "mtime": values.contentModificationDate?.timeIntervalSince1970 ?? 0
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "assets": assets], options: [.sortedKeys])
        try GameFilesystem.writePrivate(data, to: root.appending(path: ".mhg-integrity.json"))
    }

    private func outputSize(_ build: GameBuild) -> Int64 {
        let outputs = build.assets.reduce(into: [String: Int64]()) { $0[$1.name.lowercased()] = $1.size }
            .merging(build.patchAssets.reduce(into: [String: Int64]()) { $0[$1.name.lowercased()] = $1.size }) { _, new in new }
        return outputs.isEmpty ? build.downloadSize : outputs.values.reduce(0, +)
    }

    private func existingAncestor(_ value: URL) -> URL {
        var current = value
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" {
            current.deleteLastPathComponent()
        }
        return current
    }

    private var predownloadMarkerURL: URL {
        dataDirectory.appending(path: "GameDownloads/predownload.json")
    }

    private func predownloadMarker(_ build: GameBuild) -> String {
        "{\"schema\":1,\"version\":\"\(build.version)\"}"
    }

    private func predownloadReady(_ build: GameBuild) throws -> Bool {
        guard let data = try? Data(contentsOf: predownloadMarkerURL),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return value["version"] as? String == build.version
    }

    private func savedPath() async throws -> String? {
        try await database.read { db in
            try String.fetchOne(db, sql: "SELECT install_path FROM game_state WHERE id=1")
        }
    }

    private func saveState(path: String, version: String, status: GameStatus) async throws {
        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO game_state(id,install_path,version,status,updated_at) VALUES(1,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET install_path=excluded.install_path,version=excluded.version,
                status=excluded.status,updated_at=excluded.updated_at
                """, arguments: [path, version, status.rawValue, CoreDate.string(Date())])
        }
    }
}
