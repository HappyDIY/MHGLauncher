import Foundation
import Testing
@testable import MHGLauncher

@Suite("API 客户端", .serialized)
struct APIClientTests {
    @Test("发送鉴权头并解码响应")
    func authorizedRequest() async throws {
        let session = makeSession { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            let body = """
            {
              "install_path": "",
              "installed_version": "",
              "available_version": "5.8.0",
              "status": "not_installed"
            }
            """
            return response(request, status: 200, body: body)
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:1234")!,
            token: "token",
            session: session
        )
        let state: GameState = try await client.get("/v1/game/status")
        #expect(state.availableVersion == "5.8.0")
    }

    @Test("长任务使用指定超时时间")
    func customRequestTimeout() async throws {
        let session = makeSession { request in
            #expect(request.timeoutInterval == 300)
            return response(request, status: 200, body: "{\"inserted\":0}")
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:1234")!,
            token: "token",
            session: session
        )
        let result: CountResponse = try await client.post(
            "/v1/wishes/sync",
            body: CredentialRequest(credential: "credential"),
            timeout: 300
        )
        #expect(result.inserted == 0)
    }

    @Test("解码清空记录结果")
    func deleteResponse() async throws {
        let session = makeSession { request in
            #expect(request.httpMethod == "DELETE")
            return response(request, status: 200, body: "{\"deleted\":42}")
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:1234")!,
            token: "token",
            session: session
        )
        let result: CountResponse = try await client.deleteResponse("/v1/wishes")
        #expect(result.deleted == 42)
    }

    @Test("解码未登录账号响应")
    func emptyAccountResponse() async throws {
        let session = makeSession { request in
            response(request, status: 200, body: "null")
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:1234")!,
            token: "token",
            session: session
        )
        let account: Account? = try await client.get("/v1/account")
        #expect(account == nil)
    }

    @Test("将错误响应转换为统一错误")
    func errorResponse() async {
        let session = makeSession { request in
            response(
                request,
                status: 501,
                body: """
                {
                  "code": "launch_not_implemented",
                  "message": "游戏启动功能尚未实现",
                  "details": {}
                }
                """
            )
        }
        let client = APIClient(
            baseURL: URL(string: "http://127.0.0.1:1234")!,
            token: "token",
            session: session
        )
        await #expect(throws: APIErrorPayload.self) {
            let _: EmptyResponse = try await client.post("/v1/game/launch")
        }
    }

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(
        _ request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
