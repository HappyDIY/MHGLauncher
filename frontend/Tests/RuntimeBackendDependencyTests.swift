import Foundation
import Testing
@testable import MHGLauncher

@Suite("后端运行时依赖")
struct RuntimeBackendDependencyTests {
    @Test("依赖版本不一致时拒绝复用")
    func rejectsStaleDependencies() throws {
        let fixture = try CoreFixture()
        let installer = RuntimeInstaller(environment: fixture.environment)
        let app = try tempDir()
        let module = app.appending(path: "node_modules/string-argv")
        try FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: app.appending(path: "package.json"))
        #expect(!installer.backendDependenciesReady(at: app))
        try Data(#"{"dependencies":{"string-argv":"0.3.2"}}"#.utf8)
            .write(to: app.appending(path: "package.json"))
        try Data(#"{"version":"0.3.1"}"#.utf8)
            .write(to: module.appending(path: "package.json"))
        #expect(!installer.backendDependenciesReady(at: app))
        try Data(#"{"version":"0.3.2"}"#.utf8)
            .write(to: module.appending(path: "package.json"))
        #expect(installer.backendDependenciesReady(at: app))
    }
}
