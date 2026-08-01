import Foundation
import Testing
@testable import MHGLauncher

@Suite("旧版运行时标记")
struct RuntimeInstallLedgerLegacyTests {
    @Test("核心与游戏旧标记仍可识别")
    func recognizesLegacyMarkers() throws {
        let core = try tempDir()
        try create(".core-complete", under: core)
        try create("node/bin/node", under: core)
        try create("backend/app/node_modules/fixture", under: core)
        try create("backend/hpatchz", under: core)
        #expect(RuntimeInstallLedger.isReady(
            root: core, tag: "vtest", appVersion: "1.0.0", scope: .core
        ))

        let game = try tempDir()
        try create(".game-complete", under: game)
        try create("game-runtime/wine/bin/wine", under: game)
        try create("game-runtime/assets/mhypbase.dll", under: game)
        #expect(RuntimeInstallLedger.isReady(
            root: game, tag: "vtest", appVersion: "1.0.0", scope: .game
        ))
    }

    private func create(_ path: String, under root: URL) throws {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: file)
    }
}
