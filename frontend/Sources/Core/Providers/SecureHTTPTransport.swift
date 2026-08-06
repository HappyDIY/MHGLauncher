import Foundation

struct HTTPPayload: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let data: Data
    let url: URL
}

struct HTTPSHostPolicy: Sendable {
    let exactHosts: Set<String>
    let suffixes: Set<String>

    func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              url.fragment == nil,
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return exactHosts.contains(host) || suffixes.contains { host.hasSuffix("." + $0) }
    }
}

protocol HTTPTransport: Sendable {
    func send(
        _ request: URLRequest,
        policy: HTTPSHostPolicy,
        maximumBytes: Int
    ) async throws -> HTTPPayload
}

final class DenyRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class ValidatingRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: HTTPSHostPolicy
    private var redirects = 0

    init(policy: HTTPSHostPolicy) {
        self.policy = policy
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard redirects < 3, let url = request.url, policy.allows(url) else {
            completionHandler(nil)
            return
        }
        redirects += 1
        completionHandler(request)
    }
}

actor URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    func send(
        _ request: URLRequest,
        policy: HTTPSHostPolicy,
        maximumBytes: Int
    ) async throws -> HTTPPayload {
        guard maximumBytes > 0 else {
            throw LauncherCoreError(code: "response_limit_invalid", message: "网络响应限制无效")
        }
        var current = request
        let redirectDelegate = ValidatingRedirectDelegate(policy: policy)
        for redirectCount in 0...3 {
            guard let url = current.url, policy.allows(url) else {
                throw LauncherCoreError(code: "network_host_denied", message: "网络请求地址不受信任")
            }
            let (bytes, response) = try await session.bytes(
                for: current,
                delegate: redirectDelegate
            )
            guard let http = response as? HTTPURLResponse else {
                throw LauncherCoreError(code: "network_response_invalid", message: "网络响应无效")
            }
            guard policy.allows(http.url ?? url) else {
                throw LauncherCoreError(code: "network_host_denied", message: "网络响应地址不受信任")
            }
            if (300..<400).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location") {
                guard redirectCount < 3,
                      let nextURL = URL(string: location, relativeTo: url)?.absoluteURL,
                      policy.allows(nextURL) else {
                    throw LauncherCoreError(code: "network_redirect_denied", message: "网络重定向地址不受信任")
                }
                current.url = nextURL
                continue
            }
            if http.expectedContentLength > Int64(maximumBytes) {
                throw LauncherCoreError(code: "network_response_too_large", message: "网络响应超出大小限制")
            }
            var data = Data()
            data.reserveCapacity(min(max(Int(http.expectedContentLength), 0), maximumBytes))
            for try await byte in bytes {
                guard data.count < maximumBytes else {
                    throw LauncherCoreError(code: "network_response_too_large", message: "网络响应超出大小限制")
                }
                data.append(byte)
            }
            let headers = try Self.normalizedHeaders(http.allHeaderFields)
            return HTTPPayload(
                statusCode: http.statusCode,
                headers: headers,
                data: data,
                url: http.url ?? url
            )
        }
        throw LauncherCoreError(code: "network_redirect_denied", message: "网络重定向次数过多")
    }

    private static func normalizedHeaders(_ values: [AnyHashable: Any]) throws -> [String: String] {
        guard values.count <= 256 else {
            throw LauncherCoreError(code: "network_headers_invalid", message: "网络响应头超过限制")
        }
        var headers: [String: String] = [:]
        headers.reserveCapacity(values.count)
        for (rawKey, rawValue) in values {
            let key = String(describing: rawKey).lowercased()
            let value = String(describing: rawValue)
            guard !key.isEmpty,
                  key.utf8.count <= 256,
                  value.utf8.count <= 16 * 1024,
                  !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  headers[key] == nil else {
                throw LauncherCoreError(code: "network_headers_invalid", message: "网络响应头无效")
            }
            headers[key] = value
        }
        return headers
    }
}
