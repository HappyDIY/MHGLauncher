import Foundation
import Testing
@testable import MHGLauncher

@Suite("游戏运行时兼容性")
struct RuntimeGameCompatibilityTests {
    @Test("缺少 Windows 界面组件时重新安装")
    func requiresWindowsUIComponents() throws {
        let root = try tempDir()
        let runtime = InstalledRuntime(
            tag: "vtest", rootURL: root,
            backendAppURL: root.appending(path: "backend/app"),
            nodeURL: root.appending(path: "node/bin/node"),
            hpatchzURL: root.appending(path: "backend/hpatchz"),
            gameRuntimeURL: root.appending(path: "game-runtime")
        )
        let installer = RuntimeInstaller()
        #expect(!installer.gameRuntimeSupportsWindowsUI(runtime))
        for path in [
            "wine/lib/libfreetype.6.dylib",
            "wine/lib/wine/x86_64-windows/wineconsole.exe",
            "wine/lib/wine/x86_64-windows/winecfg.exe",
        ] {
            let file = runtime.gameRuntimeURL.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("fixture".utf8).write(to: file)
        }
        #expect(installer.gameRuntimeSupportsWindowsUI(runtime))
    }
}
