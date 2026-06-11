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
        body: Body
    ) async throws -> T {
        let data = try JSONEncoder.api.encode(body)
        return try await send(
            url: baseURL.appending(path: path),
            method: "POST",
            body: data
        )
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send(
            url: baseURL.appending(path: path),
            method: "POST",
            body: Data("{}".utf8)
        )
    }

    func upload<T: Decodable>(_ path: String, json: Data) async throws -> T {
        try await send(
            url: baseURL.appending(path: path),
            method: "POST",
            body: json
        )
    }

    func delete(_ path: String) async throws {
        _ = try await raw(
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
        body: Data?
    ) async throws -> T {
        let data = try await raw(url: url, method: method, body: body)
        return try JSONDecoder.api.decode(T.self, from: data)
    }

    private func raw(url: URL, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
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
        decoder.dateDecodingStrategy = .iso8601
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
