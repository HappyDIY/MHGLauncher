import Foundation
@testable import MHGLauncher

actor ScriptedTransport {
    struct Expectation: Sendable {
        let method: String
        let path: String
        let query: [String: String]
        let body: JSONValue?
        let response: APIResponse

        init<T: Encodable>(
            _ method: String,
            _ path: String,
            query: [String: String] = [:],
            body: JSONValue? = nil,
            response: T
        ) throws {
            self.method = method
            self.path = path
            self.query = query
            self.body = body
            self.response = APIResponse(status: 200, body: try JSONEncoder.api.encode(response))
        }
    }

    private var expectations: [Expectation]
    private var failure: ScriptedTransportError?

    init(_ expectations: [Expectation]) {
        self.expectations = expectations
    }

    func respond(_ request: APIRequest) throws -> APIResponse {
        guard let expected = expectations.first else {
            let error = ScriptedTransportError.unexpected("\(request.method) \(request.path)")
            failure = failure ?? error
            throw error
        }
        let components = URLComponents(string: "http://local\(request.path)")
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
        let body = try request.body.map { try JSONDecoder().decode(JSONValue.self, from: $0) }
        guard request.method == expected.method,
              components?.path == expected.path,
              query == expected.query,
              body == expected.body else {
            let error = ScriptedTransportError.mismatch(
                expected: "\(expected.method) \(expected.path) \(expected.query) \(String(describing: expected.body))",
                actual: "\(request.method) \(request.path) \(String(describing: body))"
            )
            failure = failure ?? error
            throw error
        }
        expectations.removeFirst()
        return expected.response
    }

    func verify() throws {
        if let failure { throw failure }
        guard expectations.isEmpty else {
            throw ScriptedTransportError.unconsumed(expectations.count)
        }
    }
}

enum ScriptedTransportError: Error {
    case unexpected(String)
    case mismatch(expected: String, actual: String)
    case unconsumed(Int)
}
