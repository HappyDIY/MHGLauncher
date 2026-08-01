import Testing
@testable import MHGLauncher

@Suite("运行时安装错误")
struct RuntimeInstallErrorTests {
    @Test("所有安装错误都有中文说明")
    func descriptions() {
        let errors: [RuntimeInstallError] = [
            .invalidManifest,
            .missingBundledBackend,
            .downloadFailed("node.tar.gz"),
            .checksumMismatch("node.tar.gz"),
            .archiveTraversal("../escape"),
            .processFailed("tar"),
            .unsafePromotion,
            .incompatibleCoreRuntime
        ]
        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }
}
