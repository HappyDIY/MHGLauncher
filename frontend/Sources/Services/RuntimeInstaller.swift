import Foundation

typealias RuntimeProgressHandler = @MainActor (RuntimeProgress) -> Void

final class RuntimeInstaller: @unchecked Sendable {
    let fileManager: FileManager
    let bundle: Bundle
    let environment: [String: String]

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
        if let installed = installedCoreRuntime() {
            try copyBackendApp(to: installed.backendAppURL)
            return installed
        }
        let manifest = try await loadManifest()
        let runtime = paths(tag: manifest.tag)
        let stage = stageURL(tag: manifest.tag, suffix: "core")
        try? fileManager.removeItem(at: stage)
        try fileManager.createDirectory(at: stage, withIntermediateDirectories: true)
        do {
            try copyBackendApp(to: stage.appending(path: "backend/app"))
            try await install(
                manifest: manifest,
                components: manifest.components(kind: .core),
                scope: .core,
                destination: stage,
                progress: progress
            )
            try "core".write(
                to: stage.appending(path: ".core-complete"),
                atomically: true,
                encoding: .utf8
            )
            try promote(stage: stage, destination: runtime.rootURL)
            return runtime
        } catch {
            try? fileManager.removeItem(at: stage)
            throw error
        }
    }

    func ensureGame(progress: RuntimeProgressHandler? = nil) async throws -> InstalledRuntime {
        let runtime = try await ensureCore(progress: progress)
        if gameReady(runtime) { return runtime }
        let manifest = try await loadManifest()
        let stage = stageURL(tag: manifest.tag, suffix: "game")
        try? fileManager.removeItem(at: stage)
        try fileManager.createDirectory(at: stage, withIntermediateDirectories: true)
        do {
            try await install(
                manifest: manifest,
                components: manifest.components(kind: .game),
                scope: .game,
                destination: stage,
                progress: progress
            )
            try "game".write(
                to: stage.appending(path: ".game-complete"),
                atomically: true,
                encoding: .utf8
            )
            try promoteGame(stage: stage, runtime: runtime)
            return runtime
        } catch {
            try? fileManager.removeItem(at: stage)
            throw error
        }
    }

    func isGameInstalled() -> Bool {
        let runtime = paths(tag: tag())
        return gameReady(runtime)
    }

    func installedCoreRuntime() -> InstalledRuntime? {
        let runtime = paths()
        return coreReady(runtime) ? runtime : nil
    }

    func paths(tag: String? = nil) -> InstalledRuntime {
        let tag = tag ?? self.tag()
        let root = dataDirectory()
            .appending(path: "Runtimes")
            .appending(path: tag)
        return InstalledRuntime(
            tag: tag,
            rootURL: root,
            backendAppURL: root.appending(path: "backend/app"),
            nodeURL: root.appending(path: "node/bin/node"),
            hpatchzURL: root.appending(path: "backend/hpatchz"),
            gameRuntimeURL: root.appending(path: "game-runtime")
        )
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
        for component in components {
            await report(progress, scope, component.id, "正在下载 \(component.id)", completed, total)
            let archive = try await RuntimeArchive.materialize(
                component: component,
                manifest: manifest,
                cacheURL: cacheURL(tag: manifest.tag),
                sources: sources
            )
            await report(progress, scope, component.id, "正在安装 \(component.id)", completed, total)
            try RuntimeArchive.extractTarGzip(archive, to: destination)
            completed += component.size
            await report(progress, scope, component.id, "已完成 \(component.id)", completed, total)
        }
    }

    private func loadManifest() async throws -> RuntimeManifest {
        let data = try await RuntimeManifestDownload.load(from: manifestURL(), environment: environment)
        let manifest = try JSONDecoder().decode(RuntimeManifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.tag == tag() else {
            throw RuntimeInstallError.invalidManifest
        }
        return manifest
    }

    private func copyBackendApp(to destination: URL) throws {
        let source: URL
        if let override = environment["MHG_BACKEND_APP_DIR"] {
            source = URL(fileURLWithPath: override)
        } else if let bundled = bundle.url(forResource: "app", withExtension: nil, subdirectory: "Backend") {
            source = bundled
        } else {
            throw RuntimeInstallError.missingBundledBackend
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: source, to: destination)
    }

    private func coreReady(_ runtime: InstalledRuntime) -> Bool {
        fileManager.isExecutableFile(atPath: runtime.nodeURL.path)
            && fileManager.isExecutableFile(atPath: runtime.hpatchzURL.path)
            && fileManager.fileExists(atPath: runtime.backendAppURL.appending(path: "build/server.js").path)
            && fileManager.fileExists(atPath: runtime.backendAppURL.appending(path: "node_modules").path)
            && fileManager.fileExists(atPath: runtime.rootURL.appending(path: ".core-complete").path)
    }

    private func gameReady(_ runtime: InstalledRuntime) -> Bool {
        let root = runtime.gameRuntimeURL
        return fileManager.isExecutableFile(atPath: root.appending(path: "wine/bin/wine").path)
            && fileManager.isExecutableFile(atPath: root.appending(path: "wine/bin/wineserver").path)
            && fileManager.fileExists(atPath: root.appending(path: "wine/lib/wine/x86_64-windows/winemetal.dll").path)
            && fileManager.fileExists(atPath: root.appending(path: "assets/mhypbase.dll").path)
            && fileManager.fileExists(atPath: runtime.rootURL.appending(path: ".game-complete").path)
    }

    private func promote(stage: URL, destination: URL) throws {
        let backup = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).backup")
        try? fileManager.removeItem(at: backup)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: stage, to: destination)
            try? fileManager.removeItem(at: backup)
        } catch {
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }
}
