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
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.nonempty ?? "0.1.1"
    }

    func isValid(expectedTag: String, appVersion: String) -> Bool {
        let maximumComponentSize: Int64 = 64 * 1024 * 1024 * 1024
        let maximumTotalSize: Int64 = 256 * 1024 * 1024 * 1024
        let allFiles = components.flatMap { [$0.file] + ($0.parts ?? []).map(\.file) }
        let ids = components.map(\.id), files = components.map(\.file)
        let core = Set(components(kind: .core).map(\.id))
        let game = Set(components(kind: .game).map(\.id))
        let pathsValid = !requiredPaths.isEmpty && requiredPaths.count <= 4096
            && Set(requiredPaths.map(Self.canonicalPath)).count == requiredPaths.count
            && requiredPaths.allSatisfy(Self.isSafeRelativePath)
        let componentsValid = components.allSatisfy {
            $0.size > 0 && $0.size <= maximumComponentSize
                && $0.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
                && Self.isSafeFileName($0.file) && Self.isSafeRelativePath($0.installRoot)
                && ($0.parts ?? []).count <= 128
                && ($0.parts ?? []).allSatisfy(Self.isValidPart)
                && Self.partsMatchComponent($0)
        }
        let totalSize = components.reduce(into: Int64(0)) { value, component in
            value = value > Int64.max - component.size ? Int64.max : value + component.size
        }
        return RuntimeURLPolicy.allowsAssetBase(assetBaseURL)
            && schemaVersion == 3 && tag == expectedTag && tag == "v\(appVersion)"
            && self.appVersion == appVersion && platform == "darwin" && hostArchitecture == "arm64"
            && guestArchitecture == "x86_64" && components.count <= 16
            && Set(ids).count == ids.count
            && Set(files.map(Self.canonicalPath)).count == files.count
            && Set(allFiles.map(Self.canonicalPath)).count == allFiles.count
            && core == ["hpatchz"]
            && (game.isEmpty || game == ["host", "wine", "msync", "dxmt", "mhypbase"])
            && pathsValid && componentsValid && totalSize <= maximumTotalSize
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return !normalized.isEmpty && normalized.utf8.count <= 1024
            && !normalized.hasPrefix("/")
            && !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && normalized.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 512 && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\")
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func isValidPart(_ part: RuntimeAssetPart) -> Bool {
        part.size > 0 && part.size <= 64 * 1024 * 1024 * 1024 && isSafeFileName(part.file)
            && part.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func partsMatchComponent(_ component: RuntimeComponent) -> Bool {
        guard let parts = component.parts, !parts.isEmpty else { return true }
        var total: Int64 = 0
        for part in parts {
            guard total <= Int64.max - part.size else { return false }
            total += part.size
        }
        return total == component.size
    }

    static func canonicalPath(_ path: String) -> String {
        normalizedPath(path).lowercased()
    }

    static func normalizedPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
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
    let hpatchzURL: URL
    let gameRuntimeURL: URL
}
