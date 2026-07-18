import Foundation

enum ConfigurationError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(value): value
        }
    }
}

func dotenvValue(at url: URL, key: String) throws -> String? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let content = try String(contentsOf: url, encoding: .utf8)
    var result: String?
    for rawLine in content.split(whereSeparator: { $0.isNewline }) {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        if line.hasPrefix("export ") {
            line.removeFirst("export ".count)
            line = line.trimmingCharacters(in: .whitespaces)
        }
        guard let separator = line.firstIndex(of: "=") else { continue }
        let name = line[..<separator].trimmingCharacters(in: .whitespaces)
        guard name == key else { continue }
        var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == value.last, ["\"", "'"].contains(first) {
            value.removeFirst()
            value.removeLast()
        } else if let comment = value.range(of: #"\s+#"#, options: .regularExpression) {
            value = value[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        result = String(value)
    }
    return result
}

func normalizedCloudURL(_ rawValue: String) throws -> String {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased(),
          let host = components.host?.lowercased(),
          !host.isEmpty,
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil
    else {
        throw ConfigurationError.message("MHG_CLOUD_BASE_URL 必须是无凭据、查询参数和片段的有效 URL")
    }
    let localHosts = ["localhost", "127.0.0.1", "::1"]
    guard scheme == "https" || scheme == "http" && localHosts.contains(host) else {
        throw ConfigurationError.message("MHG_CLOUD_BASE_URL 仅允许 HTTPS；本地开发可对 localhost 或回环地址使用 HTTP")
    }
    components.scheme = scheme
    guard var normalized = components.url?.absoluteString else {
        throw ConfigurationError.message("MHG_CLOUD_BASE_URL 无法规范化")
    }
    while normalized.hasSuffix("/") { normalized.removeLast() }
    return normalized
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw ConfigurationError.message("用法：configure-cloud-server.swift <.env> <Info.plist>")
    }
    let envURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let plistURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let environmentValue = ProcessInfo.processInfo.environment["MHG_CLOUD_BASE_URL"]
    let configuredValue = try environmentValue ?? dotenvValue(at: envURL, key: "MHG_CLOUD_BASE_URL")
    let cloudURL = try normalizedCloudURL(configuredValue ?? "http://localhost:3333")
    let data = try Data(contentsOf: plistURL)
    guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw ConfigurationError.message("Info.plist 格式无效")
    }
    plist["MHGCloudBaseURL"] = cloudURL
    let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try output.write(to: plistURL, options: .atomic)
    print("云端服务器：\(cloudURL)")
} catch {
    FileHandle.standardError.write(Data("云端服务器配置失败：\(error)\n".utf8))
    exit(2)
}
