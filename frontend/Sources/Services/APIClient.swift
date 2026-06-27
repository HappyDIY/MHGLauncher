import Foundation
import SwiftUI

struct APIRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?
    let timeout: TimeInterval
}

struct APIResponse: Sendable {
    let status: Int
    let body: Data
}

struct APIClient: Sendable {
    let token: String
    let transport: @Sendable (APIRequest) async throws -> APIResponse

    init(socketPath: String, token: String) {
        let socket = UnixSocketTransport(path: socketPath)
        self.token = token
        self.transport = { try await socket.send($0) }
    }

    init(
        token: String,
        transport: @escaping @Sendable (APIRequest) async throws -> APIResponse
    ) {
        self.token = token
        self.transport = transport
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(path: pathWithQuery(path, query), method: "GET", body: nil)
    }

    func post<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        timeout: TimeInterval = 60
    ) async throws -> T {
        try await send(
            path: path,
            method: "POST",
            body: JSONEncoder.api.encode(body),
            timeout: timeout
        )
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path, method: "POST", body: Data("{}".utf8))
    }

    func put<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await send(
            path: path,
            method: "PUT",
            body: JSONEncoder.api.encode(body)
        )
    }

    func upload<T: Decodable>(_ path: String, json: Data) async throws -> T {
        try await send(path: path, method: "POST", body: json)
    }

    func delete(_ path: String) async throws {
        _ = try await raw(path: path, method: "DELETE", body: nil)
    }

    func deleteResponse<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path, method: "DELETE", body: nil)
    }

    func download(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await raw(path: pathWithQuery(path, query), method: "GET", body: nil)
    }

    private func send<T: Decodable>(
        path: String,
        method: String,
        body: Data?,
        timeout: TimeInterval = 60
    ) async throws -> T {
        try JSONDecoder.api.decode(
            T.self,
            from: try await raw(path: path, method: method, body: body, timeout: timeout)
        )
    }

    private func raw(
        path: String,
        method: String,
        body: Data?,
        timeout: TimeInterval = 60
    ) async throws -> Data {
        let response = try await transport(APIRequest(
            method: method,
            path: path,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json"
            ],
            body: body,
            timeout: timeout
        ))
        guard 200..<300 ~= response.status else {
            if let payload = try? JSONDecoder.api.decode(APIErrorPayload.self, from: response.body) {
                throw payload
            }
            throw URLError(.badServerResponse)
        }
        return response.body
    }

    private func pathWithQuery(_ path: String, _ query: [URLQueryItem]) -> String {
        guard !query.isEmpty else { return path }
        var components = URLComponents()
        components.path = path
        components.queryItems = query
        return components.string ?? path
    }
}

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: APIClient? = nil
}

extension EnvironmentValues {
    var apiClient: APIClient? {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

extension JSONDecoder {
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(APIClient.decodeDate)
        return decoder
    }
}

extension JSONEncoder {
    static var api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension APIClient {
    static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let local = DateFormatter()
        local.calendar = Calendar(identifier: .gregorian)
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = local.date(from: value) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "无效日期")
    }
}
