import Foundation
import Testing
@testable import MHGLauncher

struct CoreFixture {
    let environment: [String: String]

    init(corruptFirstComponent: Bool = false, missingRuntimeTool: Bool = false) throws {
        let root = try tempDir()
        let assets = root.appending(path: "assets")
        let data = root.appending(path: "data")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let original = try [makeComponent(
            id: "hpatchz", file: "hpatchz.tar.gz", root: root,
            assets: assets,
            executable: missingRuntimeTool ? "tools/not-hpatchz" : "tools/hpatchz"
        )]
        let components = original.enumerated().map { index, component in
            guard index == 0 && corruptFirstComponent else { return component }
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
        let manifest = runtimeManifest(
            components: components,
            assets: assets,
            requiredPaths: ["tools/hpatchz"]
        )
        let manifestURL = root.appending(path: "runtime-manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        environment = [
            "MHG_DATA_DIR": data.path,
            "MHG_RUNTIME_MANIFEST_URL": manifestURL.path,
            "MHG_RUNTIME_TAG": "v0.1.1"
        ]
    }
}

func runtimeManifest(
    components: [RuntimeComponent],
    assets: URL,
    requiredPaths: [String]
) -> RuntimeManifest {
    RuntimeManifest(
        schemaVersion: 3,
        tag: "v0.1.1",
        appVersion: "0.1.1",
        platform: "darwin",
        hostArchitecture: "arm64",
        guestArchitecture: "x86_64",
        generatedAt: "1970-01-01T00:00:00Z",
        assetBaseURL: assets,
        requiredPaths: requiredPaths,
        components: components
    )
}

func makeComponent(
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
    try FileManager.default.createDirectory(
        at: target.deletingLastPathComponent(), withIntermediateDirectories: true
    )
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

func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}
