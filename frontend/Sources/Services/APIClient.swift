import Foundation

struct APIClient: Sendable {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw URLError(.badURL) }
        return try await send(url: url, method: "GET", body: Optional<Data>.none)
    }

    func post<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        timeout: TimeInterval = 60
    ) async throws -> T {
        let data = try JSONEncoder.api.encode(body)
        return try await send(
            url: baseURL.appending(path: path),
            method: "POST",
            body: data,
            timeout: timeout
        )
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send(
            url: baseURL.appending(path: path),
            method: "POST",
            body: Data("{}".utf8),
            timeout: 60
        )
    }

    func upload<T: Decodable>(_ path: String, json: Data) async throws -> T {
        try await send(
            url: baseURL.appending(path: path),
            method: "POST",
            body: json,
            timeout: 60
        )
    }

    func delete(_ path: String) async throws {
        _ = try await raw(
            url: baseURL.appending(path: path),
            method: "DELETE",
            body: nil
        )
    }

    func deleteResponse<T: Decodable>(_ path: String) async throws -> T {
        try await send(
            url: baseURL.appending(path: path),
            method: "DELETE",
            body: nil
        )
    }

    func download(_ path: String, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw URLError(.badURL) }
        return try await raw(url: url, method: "GET", body: nil)
    }

    private func send<T: Decodable>(
        url: URL,
        method: String,
        body: Data?,
        timeout: TimeInterval = 60
    ) async throws -> T {
        let data = try await raw(
            url: url,
            method: method,
            body: body,
            timeout: timeout
        )
        return try JSONDecoder.api.decode(T.self, from: data)
    }

    private func raw(
        url: URL,
        method: String,
        body: Data?,
        timeout: TimeInterval = 60
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard 200..<300 ~= http.statusCode else {
            if let payload = try? JSONDecoder.api.decode(APIErrorPayload.self, from: data) {
                throw payload
            }
            throw URLError(.badServerResponse)
        }
        return data
    }
}

extension JSONDecoder {
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            let localFormatter = DateFormatter()
            localFormatter.calendar = Calendar(identifier: .gregorian)
            localFormatter.locale = Locale(identifier: "en_US_POSIX")
            localFormatter.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
            localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = localFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无效的 ISO 8601 日期：\(value)"
            )
        }
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
