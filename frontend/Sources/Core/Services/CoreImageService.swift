import CryptoKit
import Foundation

actor CoreImageService {
    private struct RemoteImageEntry: Codable, Sendable {
        let url: String
        let digest: String
    }

    private let root: URL
    private let legacyRoot: URL
    private let indexURL: URL
    private let transport: any HTTPTransport
    private let apiBaseURL: URL
    private var remoteIndex: [String: RemoteImageEntry]

    init(
        dataDirectory: URL,
        transport: any HTTPTransport,
        apiBaseURL: URL = URL(string: "https://api.snaphutaorp.org")!
    ) throws {
        root = dataDirectory.appending(path: "resources/image-cache", directoryHint: .isDirectory)
        legacyRoot = dataDirectory.appending(path: "resources/gacha-history", directoryHint: .isDirectory)
        indexURL = root.appending(path: "index.json")
        remoteIndex = [:]
        self.transport = transport
        guard apiBaseURL.scheme?.lowercased() == "https", apiBaseURL.user == nil,
              apiBaseURL.password == nil, apiBaseURL.port == nil || apiBaseURL.port == 443,
              apiBaseURL.query == nil, apiBaseURL.fragment == nil,
              apiBaseURL.host?.isEmpty == false else {
            throw LauncherCoreError(code: "image_service_invalid", message: "图片服务地址无效")
        }
        self.apiBaseURL = apiBaseURL
        try PrivateFilesystem.ensureDirectory(root)
        remoteIndex = Self.readIndex(at: indexURL)
    }

    func cachedURL(for value: URL, digest: String = "upstream") -> URL? {
        guard let scheme = value.scheme?.lowercased(), scheme == "https",
              value.absoluteString.utf8.count <= 16 * 1024,
              digest.utf8.count <= 256,
              !digest.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (try? remoteURL(for: value)) != nil else { return nil }
        let name = Self.cacheName(remote: value.absoluteString, digest: digest)
        guard remoteIndex[name] != nil || remoteIndex.count < 50_000 else { return nil }
        if remoteIndex[name] == nil {
            remoteIndex[name] = RemoteImageEntry(url: value.absoluteString, digest: digest)
            try? GameFilesystem.writePrivate(
                try JSONEncoder.api.encode(remoteIndex), to: indexURL
            )
        }
        var components = URLComponents()
        components.scheme = MHGResourceURL.scheme
        components.host = "remote"
        components.path = "/" + name
        return components.url
    }

    func load(_ value: URL) async throws -> Data {
        let remote = try remoteURL(for: value)
        if remote.isFileURL {
            let values = try remote.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= 50 * 1024 * 1024 else {
                throw LauncherCoreError(code: "image_invalid", message: "图片资源无效")
            }
            return try Data(contentsOf: remote, options: [.mappedIfSafe])
        }
        let name = try cacheName(for: value, remote: remote)
        let destination = root.appending(path: name)
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        if GameFilesystem.regularFile(destination),
           let cached = try? Data(contentsOf: destination, options: [.mappedIfSafe]),
           Self.validImage(cached) {
            return cached
        }
        let payload = try await transport.send(
            URLRequest(url: remote, timeoutInterval: 60),
            policy: Self.imagePolicy(apiHost: apiBaseURL.host ?? "api.snaphutaorp.org"),
            maximumBytes: 50 * 1024 * 1024
        )
        guard (200..<300).contains(payload.statusCode), Self.validImage(payload.data) else {
            throw LauncherCoreError(code: "image_invalid", message: "图片资源无效")
        }
        let partial = root.appending(path: name + ".part-" + UUID().uuidString)
        try PrivateFilesystem.rejectSymbolicLinks(in: partial)
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        defer { try? PrivateFilesystem.removeRegularFileIfPresent(partial) }
        try GameFilesystem.writePrivate(payload.data, to: partial)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard GameFilesystem.regularFile(destination) else {
                throw LauncherCoreError(code: "image_cache_invalid", message: "图片缓存路径不安全")
            }
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
        } else {
            try FileManager.default.moveItem(at: partial, to: destination)
        }
        try PrivateFilesystem.setPrivateFilePermissions(destination)
        return payload.data
    }

    func cacheCharacters(_ values: [GameCharacter]) async throws {
        var urls: [URL] = []
        for value in values {
            if let url = value.iconUrl { urls.append(url) }
            guard let payload = value.payload else { continue }
            if let url = payload.base?.icon { urls.append(url) }
            if let url = payload.base?.weapon?.icon { urls.append(url) }
            if let url = payload.weapon?.icon { urls.append(url) }
            for relic in payload.relics ?? [] {
                if let url = relic.icon { urls.append(url) }
            }
            for skill in payload.skills ?? [] {
                if let url = skill.icon { urls.append(url) }
            }
            for constellation in payload.constellations ?? [] {
                if let url = constellation.icon { urls.append(url) }
            }
            urls.append(contentsOf: payload.rawFields.values.flatMap { Self.imageURLs($0) })
            urls.append(contentsOf: payload.additionalFields.values.flatMap { Self.imageURLs($0) })
        }
        var seen = Set<URL>()
        for url in urls where seen.insert(url).inserted && (try? remoteURL(for: url)) != nil {
            _ = try await load(url)
        }
    }

    private func remoteURL(for value: URL) throws -> URL {
        if value.scheme == MHGResourceURL.scheme {
            let resource = try MHGResourceURL(value)
            let categories = [
                "achievement": "AchievementIcon",
                "avatar": "AvatarIcon",
                "weapon": "EquipIcon",
                "relic": "RelicIcon",
                "skill": "Skill",
                "talent": "Talent"
            ]
            guard let host = resource.url.host else {
                throw LauncherCoreError(code: "invalid_resource_url", message: "资源地址无效")
            }
            if host == "legacy" {
                let components = resource.url.pathComponents.filter { $0 != "/" }
                guard components.count == 2,
                      components[0] == "images",
                      components[1].range(of: #"^[a-f0-9]{64}\.img$"#, options: .regularExpression) != nil else {
                    throw LauncherCoreError(code: "invalid_resource_url", message: "资源地址无效")
                }
                return try GameFilesystem.safeTarget(
                    root: legacyRoot, relativePath: components.joined(separator: "/")
                )
            }
            if host == "remote" {
                let components = resource.url.pathComponents.filter { $0 != "/" }
                guard components.count == 1,
                      let name = components.first,
                      name.range(of: Self.imageNamePattern, options: .regularExpression) != nil,
                      let entry = remoteIndex[name],
                      let remote = URL(string: entry.url),
                      (try? remoteURL(for: remote)) != nil else {
                    throw LauncherCoreError(code: "invalid_resource_url", message: "资源地址无效")
                }
                return remote
            }
            let components = resource.url.pathComponents.filter { $0 != "/" }
            guard let category = categories[host],
                  (components.count == 1 || components.count == 2),
                  let name = components.first,
                  name.range(of: #"^[A-Za-z0-9_]{1,128}$"#, options: .regularExpression) != nil,
                  components.dropFirst().allSatisfy({
                      $0.range(of: #"^[A-Za-z0-9._-]{1,128}$"#, options: .regularExpression) != nil
                  }) else {
                throw LauncherCoreError(code: "invalid_resource_url", message: "资源地址无效")
            }
            return apiBaseURL
                .appending(path: "static/raw")
                .appending(path: category)
                .appending(path: name + ".png")
        }
        guard Self.imagePolicy(apiHost: apiBaseURL.host ?? "api.snaphutaorp.org").allows(value) else {
            throw LauncherCoreError(code: "invalid_resource_url", message: "图片地址不受信任")
        }
        return value
    }

    private nonisolated static func imagePolicy(apiHost: String) -> HTTPSHostPolicy {
        HTTPSHostPolicy(
            exactHosts: [
                apiHost.lowercased(), "static.snaphutaorp.org", "mihoyo.com",
                "webstatic.mihoyo.com", "uploadstatic.mihoyo.com", "act-webstatic.mihoyo.com"
            ],
            suffixes: ["mihoyo.com"]
        )
    }

    private func cacheName(for value: URL, remote: URL) throws -> String {
        if value.scheme == MHGResourceURL.scheme {
            let resource = try MHGResourceURL(value)
            let components = resource.url.pathComponents.filter { $0 != "/" }
            if resource.url.host == "remote", let name = components.first {
                return name
            }
            if let digest = components.dropFirst().first {
                return Self.cacheName(remote: remote.absoluteString, digest: digest)
            }
        }
        return Self.cacheName(remote: remote.absoluteString, digest: "upstream")
    }

    private nonisolated static func cacheName(remote: String, digest: String) -> String {
        SHA256.hash(data: Data("\(remote)\0\(digest)".utf8)).map {
            String(format: "%02x", $0)
        }.joined() + ".img"
    }

    private nonisolated static let imageNamePattern = #"^[a-f0-9]{64}\.img$"#

    private nonisolated static func readIndex(at url: URL) -> [String: RemoteImageEntry] {
        guard GameFilesystem.regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder.api.decode([String: RemoteImageEntry].self, from: data),
              result.count <= 50_000 else { return [:] }
        return result.filter { key, value in
            key.range(of: imageNamePattern, options: .regularExpression) != nil
                && value.url.utf8.count <= 16 * 1024
                && value.digest.utf8.count <= 256
                && !value.digest.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
    }

    private nonisolated static func imageURLs(_ value: JSONValue, key: String? = nil) -> [URL] {
        switch value {
        case .string(let value) where ["icon", "image", "side_icon", "sideIcon"].contains(key):
            return URL(string: value).map { [$0] } ?? []
        case .object(let values):
            return values.flatMap { imageURLs($0.value, key: $0.key) }
        case .array(let values):
            return values.flatMap { imageURLs($0) }
        default:
            return []
        }
    }

    private nonisolated static func validImage(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 50 * 1024 * 1024 else { return false }
        let prefix = data.prefix(20).map { String(format: "%02x", $0) }.joined()
        return prefix.hasPrefix("89504e470d0a1a0a")
            || prefix.hasPrefix("ffd8ff")
            || (prefix.hasPrefix("52494646") && prefix.dropFirst(8).hasPrefix("57454250"))
    }
}
