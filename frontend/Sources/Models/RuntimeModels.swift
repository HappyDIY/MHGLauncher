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
    let generatedAt: String
    let assetBaseURL: URL
    let components: [RuntimeComponent]

    func components(kind: RuntimeComponentKind) -> [RuntimeComponent] {
        components.filter { $0.kind == kind }
    }

    static func defaultTag(bundle: Bundle = .main) -> String {
        if let version = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String, !version.isEmpty {
            return "v\(version)"
        }
        return "v0.1.0"
    }

    static func releaseManifestURL(tag: String) -> URL {
        URL(string: "https://github.com/HappyDIY/MHGLauncher/releases/download/\(tag)/runtime-manifest.json")!
    }
}

enum RuntimeInstallScope: String, Equatable, Sendable {
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
