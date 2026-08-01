import Foundation
import Testing
@testable import MHGLauncher

@Suite("全新运行时安装")
struct RuntimeFreshInstallTests {
    @Test("首次安装拒绝缺少后端依赖的运行时")
    func rejectsIncompleteCoreRuntime() async throws {
        let fixture = try CoreFixture(missingBackendDependency: true)
        let installer = RuntimeInstaller(environment: fixture.environment)
        await #expect(throws: RuntimeInstallError.incompatibleCoreRuntime) {
            _ = try await installer.ensureCore()
        }
        #expect(installer.installedCoreRuntime() == nil)
    }

    @Test("游戏运行时拒绝缺少游戏组件的清单")
    func rejectsManifestWithoutGameComponents() async throws {
        let fixture = try CoreFixture()
        let installer = RuntimeInstaller(environment: fixture.environment)
        await #expect(throws: RuntimeInstallError.invalidManifest) {
            _ = try await installer.ensureGame()
        }
    }
}
