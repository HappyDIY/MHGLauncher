import Foundation

extension RuntimeInstaller {
    func tag() -> String {
        environment["MHG_RUNTIME_TAG"] ?? RuntimeManifest.defaultTag(bundle: bundle)
    }

    func dataDirectory() -> URL {
        if let override = environment["MHG_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MHGLauncher")
    }

    func manifestURL() -> URL {
        if let override = environment["MHG_RUNTIME_MANIFEST_URL"], !override.isEmpty {
            if let url = URL(string: override), url.scheme != nil { return url }
            return URL(fileURLWithPath: override)
        }
        return RuntimeManifest.releaseManifestURL(tag: tag())
    }

    func cacheURL(tag: String) -> URL {
        dataDirectory()
            .appending(path: "RuntimeDownloads")
            .appending(path: tag)
    }

    func stageURL(tag: String, suffix: String) -> URL {
        dataDirectory()
            .appending(path: "Runtimes")
            .appending(path: ".\(tag)-\(suffix)-\(UUID().uuidString)")
    }

    func promoteGame(stage: URL, runtime: InstalledRuntime) throws {
        let gameStage = stage.appending(path: "game-runtime")
        let marker = stage.appending(path: ".game-complete")
        let backup = runtime.rootURL.appending(path: ".game-runtime.backup")
        try? fileManager.removeItem(at: backup)
        if fileManager.fileExists(atPath: runtime.gameRuntimeURL.path) {
            try fileManager.moveItem(at: runtime.gameRuntimeURL, to: backup)
        }
        do {
            try fileManager.moveItem(at: gameStage, to: runtime.gameRuntimeURL)
            try? fileManager.removeItem(at: runtime.rootURL.appending(path: ".game-complete"))
            try fileManager.moveItem(at: marker, to: runtime.rootURL.appending(path: ".game-complete"))
            try? fileManager.removeItem(at: backup)
            try? fileManager.removeItem(at: stage)
        } catch {
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: runtime.gameRuntimeURL)
            }
            throw error
        }
    }

    @MainActor
    func report(
        _ handler: RuntimeProgressHandler?,
        _ scope: RuntimeInstallScope,
        _ componentID: String,
        _ message: String,
        _ completed: Int64,
        _ total: Int64
    ) {
        handler?(RuntimeProgress(
            scope: scope,
            componentID: componentID,
            message: message,
            completed: completed,
            total: total
        ))
    }
}
