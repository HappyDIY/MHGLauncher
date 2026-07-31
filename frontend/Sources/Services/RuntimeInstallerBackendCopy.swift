import Foundation

extension RuntimeInstaller {
    func backendDependenciesReady(at app: URL) -> Bool {
        let packageURL = app.appending(path: "package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let package = try? JSONDecoder().decode(BackendPackage.self, from: data) else {
            return false
        }
        return package.dependencies.allSatisfy { name, expectedVersion in
            let installedURL = app.appending(path: "node_modules")
                .appending(path: name)
                .appending(path: "package.json")
            guard let data = try? Data(contentsOf: installedURL),
                  let installed = try? JSONDecoder().decode(InstalledPackage.self, from: data) else {
                return false
            }
            return installed.version == expectedVersion
        }
    }

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

private struct BackendPackage: Decodable {
    let dependencies: [String: String]
}

private struct InstalledPackage: Decodable {
    let version: String
}
