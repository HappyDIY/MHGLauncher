import CryptoKit
import Foundation

actor CoreImageService {
    private let root: URL
    private let transport: any HTTPTransport
    private let apiBaseURL: URL

    init(
        dataDirectory: URL,
        transport: any HTTPTransport,
        apiBaseURL: URL = URL(string: "https://api.snaphutaorp.org")!
    ) throws {
        root = dataDirectory.appending(path: "resources/image-cache", directoryHint: .isDirectory)
        self.transport = transport
        guard apiBaseURL.scheme?.lowercased() == "https", apiBaseURL.user == nil,
              apiBaseURL.password == nil, apiBaseURL.port == nil || apiBaseURL.port == 443,
              apiBaseURL.query == nil, apiBaseURL.fragment == nil,
              apiBaseURL.host?.isEmpty == false else {
            throw LauncherCoreError(code: "image_service_invalid", message: "图片服务地址无效")
        }
        self.apiBaseURL = apiBaseURL
        try PrivateFilesystem.ensureDirectory(root)
    }

    func load(_ value: URL) async throws -> Data {
        let remote = try remoteURL(for: value)
        let name = SHA256.hash(data: Data(remote.absoluteString.utf8)).map {
            String(format: "%02x", $0)
        }.joined() + ".img"
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
            guard let host = resource.url.host,
                  let category = categories[host],
                  let name = resource.url.pathComponents.last,
                  name.range(of: #"^[A-Za-z0-9_]{1,128}$"#, options: .regularExpression) != nil else {
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
            suffixes: []
        )
    }

    private nonisolated static func validImage(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 50 * 1024 * 1024 else { return false }
        let prefix = data.prefix(20).map { String(format: "%02x", $0) }.joined()
        return prefix.hasPrefix("89504e470d0a1a0a")
            || prefix.hasPrefix("ffd8ff")
            || (prefix.hasPrefix("52494646") && prefix.dropFirst(8).hasPrefix("57454250"))
    }
}
