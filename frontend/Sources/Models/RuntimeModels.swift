import Foundation

enum RuntimeComponentKind: String, Codable, Sendable {
    case core
    case game
}

struct RuntimeAssetPart: Codable, Equatable, Sendable {
    let file: String
    let size: Int64
    let sha256: String
}

struct RuntimeComponent: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: RuntimeComponentKind
    let version: String
    let file: String
    let size: Int64
    let sha256: String
    let installRoot: String
    let parts: [RuntimeAssetPart]?
}

struct RuntimeManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let tag: String
    let appVersion: String
    let platform: String
    let hostArchitecture: String
    let guestArchitecture: String
    let generatedAt: String
    let assetBaseURL: URL
    let requiredPaths: [String]
    let components: [RuntimeComponent]

    func components(kind: RuntimeComponentKind) -> [RuntimeComponent] {
        components.filter { $0.kind == kind }
    }

    static func defaultTag(bundle: Bundle = .main) -> String {
        "v\(appVersion(bundle: bundle))"
    }

    static func appVersion(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.nonempty ?? "0.1.0"
    }

    func isValid(expectedTag: String, appVersion: String) -> Bool {
        let ids = components.map(\.id), files = components.map(\.file)
        let core = Set(components(kind: .core).map(\.id))
        let game = Set(components(kind: .game).map(\.id))
        let pathsValid = !requiredPaths.isEmpty && requiredPaths.allSatisfy(Self.isSafeRelativePath)
        let componentsValid = components.allSatisfy {
            $0.size > 0 && $0.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
                && Self.isSafeFileName($0.file) && Self.isSafeRelativePath($0.installRoot)
                && ($0.parts ?? []).allSatisfy(Self.isValidPart)
        }
        return schemaVersion == 2 && tag == expectedTag && tag == "v\(appVersion)"
            && self.appVersion == appVersion && platform == "darwin" && hostArchitecture == "arm64"
            && guestArchitecture == "x86_64" && Set(ids).count == ids.count && Set(files).count == files.count
            && core == ["node", "node_modules", "hpatchz"]
            && (game.isEmpty || game == ["host", "wine", "msync", "dxmt", "mhypbase"])
            && pathsValid && componentsValid
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/")
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    private static func isValidPart(_ part: RuntimeAssetPart) -> Bool {
        part.size > 0 && isSafeFileName(part.file)
            && part.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    static func releaseManifestURL(tag: String) -> URL {
        URL(string: "https://github.com/HappyDIY/MHGLauncher/releases/download/\(tag)/runtime-manifest.json")!
    }
}

enum RuntimeInstallScope: String, Codable, Equatable, Sendable {
    case core
    case game
}

struct RuntimeProgress: Equatable, Sendable {
    let scope: RuntimeInstallScope
    let componentID: String
    let message: String
    let completed: Int64
    let total: Int64

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

struct InstalledRuntime: Equatable, Sendable {
    let tag: String
    let rootURL: URL
    let backendAppURL: URL
    let nodeURL: URL
    let hpatchzURL: URL
    let gameRuntimeURL: URL
}
