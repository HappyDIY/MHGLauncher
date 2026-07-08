import Foundation

extension RuntimeInstaller {
    func copyBackendApp(to destination: URL) throws {
        let source = try bundledBackendSource()
        let modules = destination.appending(path: "node_modules")
        let backup = destination.deletingLastPathComponent()
            .appending(path: ".backend-node-modules-\(UUID().uuidString)")

        do {
            if fileManager.fileExists(atPath: modules.path) {
                try fileManager.moveItem(at: modules, to: backup)
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: source, to: destination)
            try restoreNodeModules(from: backup, to: modules)
        } catch {
            try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try? restoreNodeModules(from: backup, to: modules)
            throw error
        }
    }

    private func bundledBackendSource() throws -> URL {
        if let override = environment["MHG_BACKEND_APP_DIR"] {
            return URL(fileURLWithPath: override)
        }
        if let bundled = bundle.url(
            forResource: "app",
            withExtension: nil,
            subdirectory: "Backend"
        ) {
            return bundled
        }
        throw RuntimeInstallError.missingBundledBackend
    }

    private func restoreNodeModules(from backup: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: backup.path) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: backup)
            return
        }
        // 后端代码热替换时，运行时资产安装的依赖目录必须保留。
        try fileManager.moveItem(at: backup, to: destination)
    }
}
