import Foundation
import Testing
@testable import MHGLauncher

@Suite("运行时压缩包安全")
struct RuntimeArchiveSecurityTests {
    @Test("拒绝指向解压目录外的符号链接")
    func rejectsEscapingSymlinkArchive() async throws {
        let root = try tempDir()
        let content = root.appending(path: "content")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: content.appending(path: "linked"),
            withDestinationURL: URL(fileURLWithPath: "/tmp")
        )
        let archive = root.appending(path: "linked.tar.gz")
        try run("/usr/bin/tar", ["-czf", archive.path, "-C", content.path, "linked"])
        await #expect(throws: RuntimeInstallError.archiveTraversal("linked")) {
            try await RuntimeArchive.validateTarGzip(archive)
        }
    }

    @Test("拒绝通过相对路径逃逸的符号链接")
    func rejectsRelativeEscapingSymlinkArchive() async throws {
        let root = try tempDir()
        let content = root.appending(path: "content")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: content.appending(path: "linked").path,
            withDestinationPath: "../outside"
        )
        let archive = root.appending(path: "relative-linked.tar.gz")
        try run("/usr/bin/tar", ["-czf", archive.path, "-C", content.path, "linked"])
        await #expect(throws: RuntimeInstallError.archiveTraversal("linked")) {
            try await RuntimeArchive.validateTarGzip(archive)
        }
    }

    @Test("允许 Wine 使用的安全相对符号链接")
    func allowsContainedSymlinkArchive() async throws {
        let root = try tempDir()
        let content = root.appending(path: "content")
        let library = content.appending(path: "lib")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: library.appending(path: "library.1.dylib"))
        try FileManager.default.createSymbolicLink(
            atPath: library.appending(path: "library.dylib").path,
            withDestinationPath: "library.1.dylib"
        )
        let archive = root.appending(path: "runtime.tar.gz")
        try run("/usr/bin/tar", ["-czf", archive.path, "-C", content.path, "."])
        try await RuntimeArchive.validateTarGzip(archive)
    }

    @Test("拒绝异常目录清单和特殊文件")
    func rejectsMalformedListingsAndSpecialFiles() {
        #expect(throws: RuntimeInstallError.archiveTraversal("压缩包目录不一致")) {
            try RuntimeArchive.validateTarEntryTypes(Data("- file\n".utf8), entries: [])
        }
        #expect(throws: RuntimeInstallError.archiveTraversal("链接或特殊文件")) {
            try RuntimeArchive.validateTarEntryTypes(
                Data("h special\n".utf8), entries: [Data("special".utf8)]
            )
        }
        #expect(throws: RuntimeInstallError.archiveTraversal("无效符号链接")) {
            try RuntimeArchive.validateTarEntryTypes(
                Data("lrwx linked\n".utf8), entries: [Data("linked".utf8)]
            )
        }
        #expect(throws: RuntimeInstallError.archiveTraversal("linked")) {
            try RuntimeArchive.validateTarEntryTypes(
                Data("lrwx linked -> \n".utf8), entries: [Data("linked".utf8)]
            )
        }
    }
}
