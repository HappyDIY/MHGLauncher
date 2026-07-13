import Foundation

typealias RuntimeProgressHandler = @MainActor (RuntimeProgress) -> Void

private struct LoadedRuntimeManifest {
    let manifest: RuntimeManifest
    let data: Data
}
final class RuntimeInstaller: @unchecked Sendable {
    let fileManager: FileManager
    let bundle: Bundle
    let environment: [String: String]
    private let gate = RuntimeInstallGate()

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.environment = environment
    }

    func ensureCore(progress: RuntimeProgressHandler? = nil) async throws -> InstalledRuntime {
        try await withTaskCancellationHandler {
            try await gate.run(scope: .core) { [self] in
                try await performEnsureCore(progress: progress)
            }
        } onCancel: {
            Task { await self.gate.cancel(scope: .core) }
        }
    }

    func ensureGame(progress: RuntimeProgressHandler? = nil) async throws -> InstalledRuntime {
        _ = try await ensureCore(progress: progress)
        return try await withTaskCancellationHandler {
            try await gate.run(scope: .game) { [self] in
                try await performEnsureGame(progress: progress)
            }
        } onCancel: {
            Task { await self.gate.cancel(scope: .game) }
        }
    }

    func isGameInstalled() -> Bool {
        recoverPromotion(tag: tag())
        return gameReady(paths(tag: tag()))
    }

    func installedCoreRuntime() -> InstalledRuntime? {
        recoverPromotion(tag: tag())
        let runtime = paths()
        return coreReady(runtime) ? runtime : nil
    }

    func paths(tag: String? = nil) -> InstalledRuntime {
        let tag = tag ?? self.tag()
        let root = dataDirectory().appending(path: "Runtimes").appending(path: tag)
        return InstalledRuntime(
            tag: tag,
            rootURL: root,
            backendAppURL: root.appending(path: "backend/app"),
            nodeURL: root.appending(path: "node/bin/node"),
            hpatchzURL: root.appending(path: "backend/hpatchz"),
            gameRuntimeURL: root.appending(path: "game-runtime")
        )
    }

    private func performEnsureCore(progress: RuntimeProgressHandler?) async throws -> InstalledRuntime {
        try Task.checkCancellation()
        if let installed = installedCoreRuntime() {
            try copyBackendApp(to: installed.backendAppURL)
            return installed
        }
        let loaded = try await loadManifest()
        let manifest = loaded.manifest
        let runtime = paths(tag: manifest.tag)
        let stage = stageURL(tag: manifest.tag, suffix: "core")
        try prepare(stage: stage)
        do {
            try copyBackendApp(to: stage.appending(path: "backend/app"))
            try await install(
                manifest: manifest,
                components: manifest.components(kind: .core),
                scope: .core,
                destination: stage,
                progress: progress
            )
            try RuntimeInstallLedger.write(
                manifest: manifest, manifestData: loaded.data, scope: .core, root: stage
            )
            try Task.checkCancellation()
            try RuntimePromotion.promote(stage: stage, destination: runtime.rootURL, fileManager: fileManager)
            return runtime
        } catch {
            try? fileManager.removeItem(at: stage)
            throw error
        }
    }

    private func performEnsureGame(progress: RuntimeProgressHandler?) async throws -> InstalledRuntime {
        let runtime = paths(tag: tag())
        if gameReady(runtime) { return runtime }
        let loaded = try await loadManifest()
        let manifest = loaded.manifest
        guard !manifest.components(kind: .game).isEmpty else {
            throw RuntimeInstallError.invalidManifest
        }
        let stage = stageURL(tag: manifest.tag, suffix: "game")
        try prepare(stage: stage)
        do {
            try fileManager.copyItem(at: runtime.rootURL, to: stage)
            try? fileManager.removeItem(at: stage.appending(path: "game-runtime"))
            try await install(
                manifest: manifest,
                components: manifest.components(kind: .game),
                scope: .game,
                destination: stage,
                progress: progress
            )
            try RuntimeInstallLedger.write(
                manifest: manifest, manifestData: loaded.data, scope: .game, root: stage
            )
            try Task.checkCancellation()
            try RuntimePromotion.promote(stage: stage, destination: runtime.rootURL, fileManager: fileManager)
            return runtime
        } catch {
            try? fileManager.removeItem(at: stage)
            throw error
        }
    }

    private func install(
        manifest: RuntimeManifest,
        components: [RuntimeComponent],
        scope: RuntimeInstallScope,
        destination: URL,
        progress: RuntimeProgressHandler?
    ) async throws {
        let total = components.map(\.size).reduce(0, +)
        var completed: Int64 = 0
        if let first = components.first {
            await report(progress, scope, first.id, "正在测速下载源", completed, total)
        }
        let sources = await RuntimeMirrorBenchmarker.ranked(
            RuntimeMirrorCatalog.sources(for: manifest.assetBaseURL, environment: environment),
            probeFile: components.first?.file
        )
        try Task.checkCancellation()
        for component in components {
            await report(progress, scope, component.id, "正在下载 \(component.id)", completed, total)
            let archive = try await RuntimeArchive.materialize(
                component: component,
                manifest: manifest,
                cacheURL: cacheURL(tag: manifest.tag),
                sources: sources
            )
            try Task.checkCancellation()
            await report(progress, scope, component.id, "正在安装 \(component.id)", completed, total)
            try RuntimeArchive.extractTarGzip(archive, to: destination)
            try Task.checkCancellation()
            completed += component.size
            await report(progress, scope, component.id, "已完成 \(component.id)", completed, total)
        }
    }

    private func loadManifest() async throws -> LoadedRuntimeManifest {
        let data = try await RuntimeManifestDownload.load(from: manifestURL(), environment: environment)
        let manifest = try JSONDecoder().decode(RuntimeManifest.self, from: data)
        let version = RuntimeManifest.appVersion(bundle: bundle)
        guard manifest.isValid(expectedTag: tag(), appVersion: version) else {
            throw RuntimeInstallError.invalidManifest
        }
        return LoadedRuntimeManifest(manifest: manifest, data: data)
    }

    private func coreReady(_ runtime: InstalledRuntime) -> Bool {
        RuntimeInstallLedger.isReady(
            root: runtime.rootURL,
            tag: runtime.tag,
            appVersion: RuntimeManifest.appVersion(bundle: bundle),
            scope: .core
        ) && fileManager.fileExists(atPath: runtime.backendAppURL.appending(path: "build/server.js").path)
    }

    private func gameReady(_ runtime: InstalledRuntime) -> Bool {
        RuntimeInstallLedger.isReady(
            root: runtime.rootURL,
            tag: runtime.tag,
            appVersion: RuntimeManifest.appVersion(bundle: bundle),
            scope: .game
        )
    }

    private func prepare(stage: URL) throws {
        try? fileManager.removeItem(at: stage)
        try fileManager.createDirectory(at: stage.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}
