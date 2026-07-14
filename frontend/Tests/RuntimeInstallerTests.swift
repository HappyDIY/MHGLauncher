import Foundation
import CryptoKit
import Testing
@testable import MHGLauncher

@Suite("运行时安装")
struct RuntimeInstallerTests {
    @Test("后端启动环境指向已安装运行时")
    func backendEnvironment() {
        let runtime = InstalledRuntime(
            tag: "vtest",
            rootURL: URL(fileURLWithPath: "/tmp/runtime"),
            backendAppURL: URL(fileURLWithPath: "/tmp/runtime/backend/app"),
            nodeURL: URL(fileURLWithPath: "/tmp/runtime/node/bin/node"),
            hpatchzURL: URL(fileURLWithPath: "/tmp/runtime/backend/hpatchz"),
            gameRuntimeURL: URL(fileURLWithPath: "/tmp/runtime/game-runtime")
        )
        let environment = BackendProcess.environment(
            token: "token",
            socketPath: "/tmp/test.sock",
            runtime: runtime,
            base: ["MHG_DATA_DIR": "/tmp/data"]
        )
        #expect(environment["NODE_ENV"] == "production")
        #expect(environment["MHG_HPATCHZ"] == "/tmp/runtime/backend/hpatchz")
        #expect(environment["MHG_RUNTIME_ROOT"] == "/tmp/runtime/game-runtime")
        #expect(environment["MHG_DATA_DIR"] == "/tmp/data")
    }

    @Test("拒绝包含目录穿越路径的压缩包")
    func rejectsTraversalArchive() async throws {
        let root = try tempDir()
        let parent = root.appending(path: "parent")
        let child = parent.appending(path: "child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("bad".utf8).write(to: parent.appending(path: "evil"))
        let archive = root.appending(path: "bad.tar.gz")
        try run("/usr/bin/tar", ["-czf", archive.path, "-C", child.path, "../evil"])
        #expect(throws: RuntimeInstallError.archiveTraversal("../evil")) {
            try await RuntimeArchive.validateTarGzip(archive)
        }
    }

    @Test("按清单安装核心运行时")
    func installsCoreRuntime() async throws {
        let fixture = try CoreFixture()
        let installer = RuntimeInstaller(environment: fixture.environment)
        let runtime = try await installer.ensureCore()
        #expect(FileManager.default.isExecutableFile(atPath: runtime.nodeURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: runtime.hpatchzURL.path))
        #expect(FileManager.default.fileExists(atPath: runtime.backendAppURL.appending(path: "build/server.js").path))
        #expect(FileManager.default.fileExists(atPath: runtime.backendAppURL.appending(path: "node_modules").path))
    }

    @Test("已安装相同版本无需读取清单")
    func reusesInstalledCore() async throws {
        let fixture = try CoreFixture(), installer = RuntimeInstaller(environment: fixture.environment)
        let installed = try await installer.ensureCore()
        #expect(installer.installedCoreRuntime() == installed)
        try FileManager.default.removeItem(atPath: fixture.environment["MHG_RUNTIME_MANIFEST_URL"]!)
        try Data("server-updated".utf8).write(to: URL(fileURLWithPath: fixture.environment["MHG_BACKEND_APP_DIR"]!).appending(path: "build/server.js"))
        let reused = try await installer.ensureCore()
        let active = try Data(contentsOf: reused.backendAppURL.appending(path: "build/server.js"))
        #expect(installed == reused)
        #expect(String(decoding: active, as: UTF8.self) == "server-updated")
        #expect(FileManager.default.fileExists(atPath: reused.backendAppURL.appending(path: "node_modules/.keep").path))
        #expect(installer.installedCoreRuntime() == reused)
    }

    @Test("下载产物校验失败时中止")
    func checksumMismatch() async throws {
        let fixture = try CoreFixture(corruptFirstComponent: true)
        let installer = RuntimeInstaller(environment: fixture.environment)
        await #expect(throws: RuntimeInstallError.checksumMismatch("node.tar.gz")) {
            _ = try await installer.ensureCore()
        }
    }

    @Test("官方 Release 使用已验证镜像池")
    func releaseMirrors() {
        let base = URL(string: "https://github.com/HappyDIY/MHGLauncher/releases/download/v0.1.0")!
        let sources = RuntimeMirrorCatalog.sources(for: base, environment: [:])
        #expect(sources.count == 6)
        #expect(sources.last?.id == "github")
        #expect(sources.contains { $0.baseURL.host == "github.boki.moe" })
    }

    @Test("镜像清单必须通过签名验证")
    func verifiesManifestSignature() throws {
        let key = Curve25519.Signing.PrivateKey(), manifest = Data("manifest".utf8)
        let signature = try key.signature(for: manifest)
        #expect(RuntimeManifestVerifier.isValid(manifest, signature: signature, publicKey: key.publicKey.rawRepresentation))
        #expect(!RuntimeManifestVerifier.isValid(Data("changed".utf8), signature: signature, publicKey: key.publicKey.rawRepresentation))
    }

    @Test("下载源失败时切换镜像")
    func fallsBackToNextSource() async throws {
        let root = try tempDir(), assets = root.appending(path: "assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let component = try makeComponent(id: "node", file: "node.tar.gz", root: root, assets: assets)
        let manifest = runtimeManifest(
            components: [component], assets: assets, requiredPaths: [component.installRoot]
        )
        let archive = try await RuntimeArchive.materialize(
            component: component, manifest: manifest, cacheURL: root.appending(path: "cache"),
            sources: [
                RuntimeDownloadSource(id: "failed", baseURL: root.appending(path: "missing")),
                RuntimeDownloadSource(id: "available", baseURL: assets)
            ]
        )
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("旧版清单不再视为可安装")
    func rejectsLegacyManifest() throws {
        let root = try tempDir()
        let component = RuntimeComponent(
            id: "node", kind: .core, version: "test", file: "node.tar.gz",
            size: 1, sha256: String(repeating: "0", count: 64),
            installRoot: "node/bin/node", parts: nil
        )
        let valid = runtimeManifest(
            components: [component], assets: root, requiredPaths: ["node/bin/node"]
        )
        let legacy = RuntimeManifest(
            schemaVersion: 1, tag: valid.tag, appVersion: valid.appVersion,
            platform: valid.platform, hostArchitecture: valid.hostArchitecture,
            guestArchitecture: valid.guestArchitecture, generatedAt: valid.generatedAt,
            assetBaseURL: valid.assetBaseURL, requiredPaths: valid.requiredPaths,
            components: valid.components
        )
        #expect(!legacy.isValid(expectedTag: "v0.1.0", appVersion: "0.1.0"))
    }

    @Test("安装标记拒绝符号链接必需路径")
    func markerRejectsSymlink() throws {
        let root = try tempDir()
        let target = root.appending(path: "target")
        try Data("ok".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "node"), withDestinationURL: target
        )
        let record = RuntimeInstallRecord(
            schemaVersion: 2, tag: "v0.1.0", appVersion: "0.1.0",
            manifestDigest: String(repeating: "0", count: 64),
            scope: .core, requiredPaths: ["node"]
        )
        try JSONEncoder().encode(record).write(
            to: root.appending(path: RuntimeInstallLedger.markerName)
        )
        #expect(!RuntimeInstallLedger.isReady(
            root: root, tag: "v0.1.0", appVersion: "0.1.0", scope: .core
        ))
    }

    @Test("提升失败恢复旧运行时")
    func promotionFailureRollsBack() throws {
        let root = try tempDir()
        let destination = root.appending(path: "v0.1.0")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appending(path: "value"))
        #expect(throws: (any Error).self) {
            try RuntimePromotion.promote(
                stage: root.appending(path: "missing"),
                destination: destination,
                fileManager: .default
            )
        }
        let value = try Data(contentsOf: destination.appending(path: "value"))
        #expect(String(decoding: value, as: UTF8.self) == "old")
    }

    @Test("并发安装共享同一事务")
    func coalescesConcurrentInstall() async throws {
        let fixture = try CoreFixture()
        let installer = RuntimeInstaller(environment: fixture.environment)
        async let first = installer.ensureCore()
        async let second = installer.ensureCore()
        let results = try await [first, second]
        #expect(results[0] == results[1])
    }
}
