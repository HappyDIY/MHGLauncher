import Testing
@testable import MHGLauncher

@Suite("运行时安装错误")
struct RuntimeInstallErrorTests {
    @Test("所有安装错误都有中文说明")
    func descriptions() {
        let errors: [RuntimeInstallError] = [
            .invalidManifest,
            .missingRuntimeTool,
            .downloadFailed("hpatchz.tar.gz"),
            .checksumMismatch("hpatchz.tar.gz"),
            .archiveTraversal("../escape"),
            .processFailed("tar"),
            .unsafePromotion,
            .incompatibleCoreRuntime
        ]
        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }
}
