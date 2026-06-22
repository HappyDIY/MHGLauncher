import Foundation
import Testing
@testable import MHGLauncher

@Suite("API 客户端")
struct APIClientTests {
    @Test("发送鉴权头并解码响应")
    func authorizedRequest() async throws {
        let client = makeClient { request in
            #expect(request.headers["Authorization"] == "Bearer token")
            return json(200, """
            {"install_path":"","installed_version":"","available_version":"5.8.0","status":"not_installed"}
            """)
        }
        let state: GameState = try await client.get("/v1/game/status")
        #expect(state.availableVersion == "5.8.0")
    }

    @Test("长任务使用指定超时时间")
    func customRequestTimeout() async throws {
        let client = makeClient { request in
            #expect(request.timeout == 300)
            return json(200, "{\"inserted\":0}")
        }
        let result: CountResponse = try await client.post(
            "/v1/wishes/tasks/sync",
            body: CredentialRequest(credential: "credential"),
            timeout: 300
        )
        #expect(result.inserted == 0)
    }

    @Test("请求编码包含查询参数")
    func queryEncoding() async throws {
        let client = makeClient { request in
            #expect(request.path == "/v1/wishes?uid=100000001")
            return json(200, "[]")
        }
        let records: [WishRecord] = try await client.get(
            "/v1/wishes",
            query: [URLQueryItem(name: "uid", value: "100000001")]
        )
        #expect(records.isEmpty)
    }

    @Test("解码清空记录结果")
    func deleteResponse() async throws {
        let client = makeClient { request in
            #expect(request.method == "DELETE")
            return json(200, "{\"deleted\":42}")
        }
        let result: CountResponse = try await client.deleteResponse("/v1/wishes")
        #expect(result.deleted == 42)
    }

    @Test("解码未登录账号响应")
    func emptyAccountResponse() async throws {
        let client = makeClient { _ in json(200, "null") }
        let account: Account? = try await client.get("/v1/account")
        #expect(account == nil)
    }

    @Test("将错误响应转换为统一错误")
    func errorResponse() async {
        let client = makeClient { _ in
            json(501, """
            {"code":"launch_not_implemented","message":"游戏启动功能尚未实现","details":{}}
            """)
        }
        await #expect(throws: APIErrorPayload.self) {
            let _: EmptyResponse = try await client.post("/v1/game/launch")
        }
    }

    private func makeClient(
        handler: @escaping @Sendable (APIRequest) async throws -> APIResponse
    ) -> APIClient {
        APIClient(token: "token", transport: handler)
    }
}

private func json(_ status: Int, _ body: String) -> APIResponse {
    APIResponse(status: status, body: Data(body.utf8))
}
