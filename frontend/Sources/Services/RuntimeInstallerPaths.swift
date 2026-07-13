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

    func recoverPromotion(tag: String) {
        let parent = dataDirectory().appending(path: "Runtimes")
        let journal = parent.appending(path: ".\(tag).promotion.json")
        try? RuntimePromotion.recover(journal: journal, fileManager: fileManager)
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
