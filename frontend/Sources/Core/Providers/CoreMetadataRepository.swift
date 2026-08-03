import Foundation

struct CoreMetadataSnapshot: Sendable {
    let root: URL
    let oid: String
    let activatedAt: Date
}

actor CoreMetadataRepository {
    private let dataDirectory: URL
    private let discoveryBaseURL: URL?
    private let configuredMirrors: [URL]
    private let transport: any HTTPTransport
    private let git = LibGitRepository()
    private let fileManager = FileManager.default

    init(
        dataDirectory: URL,
        discoveryBaseURL: URL?,
        configuredMirrors: [URL],
        transport: any HTTPTransport
    ) {
        self.dataDirectory = dataDirectory
        self.discoveryBaseURL = discoveryBaseURL
        self.configuredMirrors = configuredMirrors
        self.transport = transport
    }

    func activeSnapshot() -> CoreMetadataSnapshot? {
        let root = destination
        guard GameFilesystem.regularFile(root.appending(path: ".mhg-resource.json")),
              let data = try? Data(contentsOf: root.appending(path: ".mhg-resource.json")),
              let value = try? JSONDecoder.api.decode(Descriptor.self, from: data),
              value.oid.range(of: "^[a-f0-9]{40,64}$", options: .regularExpression) != nil,
              (try? validateNormalized(root)) != nil else { return nil }
        return CoreMetadataSnapshot(root: root, oid: value.oid, activatedAt: value.activatedAt)
    }

    func sync(force: Bool) async throws -> CoreMetadataSnapshot {
        let mirrors = try await mirrors()
        guard !mirrors.isEmpty else {
            throw LauncherCoreError(code: "metadata_mirror_missing", message: "没有可用的 HTTPS 资料镜像")
        }
        var lastError: Error?
        for mirror in mirrors {
            let clone = resourcesRoot.appending(path: "Snap.Metadata.mhg-clone-\(UUID().uuidString)")
            let normalized = resourcesRoot.appending(path: "Snap.Metadata.mhg-staging-\(UUID().uuidString)")
            defer {
                try? fileManager.removeItem(at: clone)
                try? fileManager.removeItem(at: normalized)
            }
            do {
                let oid = try await git.shallowClone(from: mirror, to: clone, maximumBytes: 128 * 1024 * 1024)
                if !force, let active = activeSnapshot(), active.oid == oid { return active }
                try validateRepository(clone)
                try normalize(clone, into: normalized, oid: oid)
                try activate(normalized)
                return CoreMetadataSnapshot(root: destination, oid: oid, activatedAt: Date())
            } catch {
                lastError = error
            }
        }
        if let error = lastError as? LauncherCoreError { throw error }
        throw LauncherCoreError(code: "metadata_sync_failed", message: "游戏资料同步失败")
    }

    private var resourcesRoot: URL { dataDirectory.appending(path: "resources") }
    private var destination: URL { resourcesRoot.appending(path: "Snap.Metadata") }

    private func mirrors() async throws -> [URL] {
        var output = configuredMirrors.filter(Self.secureMirror)
        if let discoveryBaseURL,
           discoveryBaseURL.scheme == "https",
           discoveryBaseURL.user == nil,
           discoveryBaseURL.password == nil,
           let host = discoveryBaseURL.host?.lowercased() {
            var components = URLComponents(url: discoveryBaseURL, resolvingAgainstBaseURL: false)
            components?.path = "/git-repository/all"
            components?.queryItems = [.init(name: "name", value: "Snap.Metadata")]
            if let url = components?.url {
                let payload = try await transport.send(
                    URLRequest(url: url, timeoutInterval: 30),
                    policy: HTTPSHostPolicy(exactHosts: [host], suffixes: []),
                    maximumBytes: 1024 * 1024
                )
                guard (200..<300).contains(payload.statusCode),
                      let object = try JSONSerialization.jsonObject(with: payload.data) as? [String: Any],
                      (object["code"] as? NSNumber)?.intValue == 0,
                      let values = object["data"] as? [[String: Any]], values.count <= 32 else {
                    throw LauncherCoreError(code: "metadata_discovery_invalid", message: "资料镜像响应无效")
                }
                output += values.compactMap { value in
                    (value["https_url"] as? String).flatMap(URL.init(string:)).flatMap { Self.secureMirror($0) ? $0 : nil }
                }
            }
        }
        var seen = Set<String>()
        return output.filter { seen.insert($0.absoluteString).inserted }
    }

    private func validateRepository(_ root: URL) throws {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw invalid("资料仓库无法读取")
        }
        var count = 0
        var total = 0
        while let url = enumerator.nextObject() as? URL {
            if url.pathComponents.contains(".git") { continue }
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw invalid("资料仓库包含不安全的文件")
            }
            count += 1
            total += values.fileSize ?? 0
            guard count <= 10_000, (values.fileSize ?? 0) <= 8 * 1024 * 1024,
                  total <= 384 * 1024 * 1024 else { throw invalid("资料仓库大小超过限制") }
        }
        let chs = root.appending(path: "Genshin/CHS")
        let metaURL = chs.appending(path: "Meta.json")
        guard let meta = try JSONSerialization.jsonObject(with: boundedData(metaURL)) as? [String: String] else {
            throw invalid("资料摘要文件无效")
        }
        let required = ["GachaEvent", "Weapon", "Reliquary", "Achievement", "AchievementGoal"]
        let avatars = meta.keys.filter { $0.hasPrefix("Avatar/") }
        guard !avatars.isEmpty else { throw invalid("资料摘要缺少角色数据") }
        for key in required + avatars {
            guard key.range(of: #"^(?:GachaEvent|Weapon|Reliquary|Achievement|AchievementGoal|Avatar/[1-9][0-9]{0,15})$"#, options: .regularExpression) != nil,
                  let expected = meta[key], expected.range(of: "^[A-F0-9]{16}$", options: .regularExpression) != nil else {
                throw invalid("资料摘要包含非法字段")
            }
            let data = try boundedData(chs.appending(path: "\(key).json"))
            let normalized = Data(String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r\n").utf8)
            guard [data, normalized].map(CoreHash.xxHash64).contains(expected.lowercased()) else {
                throw invalid("资料文件校验失败")
            }
            _ = try JSONSerialization.jsonObject(with: data)
        }
    }

    private func normalize(_ source: URL, into output: URL, oid: String) throws {
        try PrivateFilesystem.ensureDirectory(output)
        let chs = source.appending(path: "Genshin/CHS")
        let mappings = [
            ("Achievement.json", "achievement.json"),
            ("AchievementGoal.json", "achievement_goals.json"),
            ("GachaEvent.json", "gacha_events.json")
        ]
        for (input, name) in mappings {
            try GameFilesystem.writePrivate(try boundedData(chs.appending(path: input)), to: output.appending(path: name))
        }
        var items: [String: [Any]] = [:]
        guard let weapons = try JSONSerialization.jsonObject(with: boundedData(chs.appending(path: "Weapon.json"))) as? [[String: Any]],
              weapons.count <= 20_000 else { throw invalid("武器资料无效") }
        for weapon in weapons {
            guard let id = weapon["Id"] as? NSNumber, let name = weapon["Name"] as? String,
                  let rank = weapon["RankLevel"] as? NSNumber, let icon = weapon["Icon"] as? String else {
                throw invalid("武器资料无效")
            }
            items[id.stringValue] = [name, "武器", rank.intValue, icon]
        }
        let avatarRoot = chs.appending(path: "Avatar")
        let avatars = try fileManager.contentsOfDirectory(at: avatarRoot, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { $0.pathExtension == "json" }
        guard avatars.count <= 20_000 else { throw invalid("角色资料无效") }
        for url in avatars {
            guard let avatar = try JSONSerialization.jsonObject(with: boundedData(url)) as? [String: Any],
                  let id = avatar["Id"] as? NSNumber, let name = avatar["Name"] as? String,
                  let quality = avatar["Quality"] as? NSNumber, let icon = avatar["Icon"] as? String else {
                throw invalid("角色资料无效")
            }
            items[id.stringValue] = [name, "角色", quality.intValue >= 5 ? 5 : quality.intValue, icon]
        }
        try GameFilesystem.writePrivate(
            JSONSerialization.data(withJSONObject: items, options: [.sortedKeys]),
            to: output.appending(path: "gacha_items.json")
        )
        let descriptor = Descriptor(oid: oid, activatedAt: Date())
        try GameFilesystem.writePrivate(JSONEncoder.api.encode(descriptor), to: output.appending(path: ".mhg-resource.json"))
        try validateNormalized(output)
    }

    private func validateNormalized(_ root: URL) throws {
        for name in ["achievement.json", "achievement_goals.json", "gacha_events.json", "gacha_items.json"] {
            let url = root.appending(path: name)
            guard GameFilesystem.regularFile(url) else { throw invalid("资料缓存不完整") }
            _ = try JSONSerialization.jsonObject(with: boundedData(url))
        }
    }

    private func activate(_ staging: URL) throws {
        try PrivateFilesystem.ensureDirectory(resourcesRoot)
        let backup = resourcesRoot.appending(path: "Snap.Metadata.mhg-backup")
        try? fileManager.removeItem(at: backup)
        let hadCurrent = fileManager.fileExists(atPath: destination.path)
        if hadCurrent { try fileManager.moveItem(at: destination, to: backup) }
        do {
            try fileManager.moveItem(at: staging, to: destination)
            try? fileManager.removeItem(at: backup)
        } catch {
            try? fileManager.removeItem(at: destination)
            if hadCurrent { try? fileManager.moveItem(at: backup, to: destination) }
            throw error
        }
    }

    private func boundedData(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 8 * 1024 * 1024 else { throw invalid("资料文件大小无效") }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func secureMirror(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.nonempty != nil
            && url.user == nil && url.password == nil && url.port == nil
    }

    private func invalid(_ message: String) -> LauncherCoreError {
        LauncherCoreError(code: "metadata_invalid", message: message)
    }
}

private struct Descriptor: Codable, Sendable {
    let oid: String
    let activatedAt: Date
}
