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
    func rejectsTraversalArchive() throws {
        let root = try tempDir()
        let parent = root.appending(path: "parent")
        let child = parent.appending(path: "child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("bad".utf8).write(to: parent.appending(path: "evil"))
        let archive = root.appending(path: "bad.tar.gz")
        try run("/usr/bin/tar", ["-czf", archive.path, "-C", child.path, "../evil"])
        #expect(throws: RuntimeInstallError.archiveTraversal("../evil")) {
            try RuntimeArchive.validateTarGzip(archive)
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
        try FileManager.default.removeItem(atPath: fixture.environment["MHG_RUNTIME_MANIFEST_URL"]!)
        let reused = try await installer.ensureCore()
        #expect(installed == reused)
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
        let manifest = RuntimeManifest(schemaVersion: 1, tag: "vtest", generatedAt: "", assetBaseURL: assets, components: [component])
        let archive = try await RuntimeArchive.materialize(
            component: component, manifest: manifest, cacheURL: root.appending(path: "cache"),
            sources: [
                RuntimeDownloadSource(id: "failed", baseURL: root.appending(path: "missing")),
                RuntimeDownloadSource(id: "available", baseURL: assets)
            ]
        )
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }
}

private struct CoreFixture {
    let environment: [String: String]

    init(corruptFirstComponent: Bool = false) throws {
        let root = try tempDir()
        let assets = root.appending(path: "assets")
        let backend = root.appending(path: "backend-app")
        let data = root.appending(path: "data")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backend.appending(path: "build"), withIntermediateDirectories: true)
        try Data("server".utf8).write(to: backend.appending(path: "build/server.js"))
        let components = try [
            makeComponent(id: "node", file: "node.tar.gz", root: root, assets: assets, executable: "node/bin/node"),
            makeComponent(id: "node_modules", file: "modules.tar.gz", root: root, assets: assets, marker: "backend/app/node_modules/.keep"),
            makeComponent(id: "hpatchz", file: "hpatchz.tar.gz", root: root, assets: assets, executable: "backend/hpatchz")
        ].enumerated().map { index, component in
            if index == 0 && corruptFirstComponent {
                return RuntimeComponent(
                    id: component.id,
                    kind: component.kind,
                    version: component.version,
                    file: component.file,
                    size: component.size,
                    sha256: String(repeating: "0", count: 64),
                    installRoot: component.installRoot,
                    parts: nil
                )
            }
            return component
        }
        let manifest = RuntimeManifest(
            schemaVersion: 1,
            tag: "vtest",
            generatedAt: "1970-01-01T00:00:00Z",
            assetBaseURL: assets,
            components: components
        )
        let manifestURL = root.appending(path: "runtime-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        environment = [
            "MHG_DATA_DIR": data.path,
            "MHG_BACKEND_APP_DIR": backend.path,
            "MHG_RUNTIME_MANIFEST_URL": manifestURL.path,
            "MHG_RUNTIME_TAG": "vtest"
        ]
    }
}

private func makeComponent(
    id: String,
    file: String,
    root: URL,
    assets: URL,
    executable: String? = nil,
    marker: String? = nil
) throws -> RuntimeComponent {
    let source = root.appending(path: "\(id)-source")
    let relative = executable ?? marker ?? ".keep"
    let target = source.appending(path: relative)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(id.utf8).write(to: target)
    if executable != nil {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
    }
    let archive = assets.appending(path: file)
    try run("/usr/bin/tar", ["--format=ustar", "-C", source.path, "-czf", archive.path, "."])
    return RuntimeComponent(
        id: id,
        kind: .core,
        version: "test",
        file: file,
        size: Int64(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
        sha256: try RuntimeArchive.sha256(archive),
        installRoot: relative,
        parts: nil
    )
}

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}
