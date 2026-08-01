import Foundation
import Testing
@testable import MHGLauncher

@Suite("运行时安装标记符号链接")
struct RuntimeInstallLedgerSymlinkTests {
    @Test("接受 Wine 自带的 wineboot 链接")
    func acceptsWinebootSymlink() throws {
        let root = try tempDir()
        let bin = root.appending(path: "game-runtime/wine/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("wine".utf8).write(to: bin.appending(path: "wine"))
        try FileManager.default.createSymbolicLink(
            atPath: bin.appending(path: "wineboot").path, withDestinationPath: "wine"
        )
        try writeMarker(root: root, path: "game-runtime/wine/bin/wineboot")

        #expect(RuntimeInstallLedger.isReady(
            root: root, tag: "v0.1.1", appVersion: "0.1.1", scope: .game
        ))
    }

    @Test("拒绝 Wine 路径上的其他链接目标")
    func rejectsUnexpectedWinebootTarget() throws {
        let root = try tempDir()
        let bin = root.appending(path: "game-runtime/wine/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("other".utf8).write(to: bin.appending(path: "other"))
        try FileManager.default.createSymbolicLink(
            atPath: bin.appending(path: "wineboot").path, withDestinationPath: "other"
        )
        try writeMarker(root: root, path: "game-runtime/wine/bin/wineboot")

        #expect(!RuntimeInstallLedger.isReady(
            root: root, tag: "v0.1.1", appVersion: "0.1.1", scope: .game
        ))
    }

    private func writeMarker(root: URL, path: String) throws {
        let record = RuntimeInstallRecord(
            schemaVersion: 2, tag: "v0.1.1", appVersion: "0.1.1",
            manifestDigest: String(repeating: "0", count: 64),
            scope: .game, requiredPaths: [path]
        )
        try JSONEncoder().encode(record).write(
            to: root.appending(path: RuntimeInstallLedger.markerName)
        )
    }
}
