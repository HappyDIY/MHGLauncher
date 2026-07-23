import Foundation
import Testing
@testable import MHGLauncher

@Suite("运行时压缩包安全")
struct RuntimeArchiveSecurityTests {
    @Test("拒绝包含符号链接的压缩包")
    func rejectsSymlinkArchive() async throws {
        let root = try tempDir()
        let content = root.appending(path: "content")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: content.appending(path: "linked"),
            withDestinationURL: URL(fileURLWithPath: "/tmp")
        )
        let archive = root.appending(path: "linked.tar.gz")
        try run("/usr/bin/tar", ["-czf", archive.path, "-C", content.path, "linked"])
        await #expect(throws: RuntimeInstallError.archiveTraversal("链接或特殊文件")) {
            try await RuntimeArchive.validateTarGzip(archive)
        }
    }
}
