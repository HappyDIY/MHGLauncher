import Foundation
import Testing
@testable import MHGLauncher

@Suite("运行时下载回退")
struct RuntimeArchiveFallbackTests {
    @Test("镜像文件失效时回退清单官方源")
    func fallsBackToManifestSource() async throws {
        let root = try tempDir()
        let assets = root.appending(path: "assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let component = try makeComponent(
            id: "runtime", file: "runtime.tar.gz", root: root, assets: assets
        )
        let manifest = runtimeManifest(
            components: [component], assets: assets, requiredPaths: [component.installRoot]
        )
        let archive = try await RuntimeArchive.materialize(
            component: component,
            manifest: manifest,
            cacheURL: root.appending(path: "cache"),
            sources: [RuntimeDownloadSource(id: "stale", baseURL: root.appending(path: "missing"))]
        )
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }
}
