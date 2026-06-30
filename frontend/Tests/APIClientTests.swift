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

    @Test("后端错误允许混合类型详情")
    func errorPayloadWithMixedDetails() async throws {
        let client = makeClient { _ in
            json(422, #"{"code":"disk_space_insufficient","message":"磁盘空间不足","details":{"required":130,"sufficient":false}}"#)
        }
        await #expect(throws: APIErrorPayload.self) {
            let _: EmptyResponse = try await client.get("/v1/game/space-check")
        }
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

    @Test("编码启动参数并解码会话")
    func gameLaunchRequest() async throws {
        let client = makeClient { request in
            let body = try #require(request.body)
            let value = try JSONDecoder.api.decode(StartGameLaunchRequest.self, from: body)
            #expect(value.performanceProfile == .optimized)
            #expect(value.metalHud)
            #expect(value.credential == "stoken=fixture; mid=mid")
            return json(202, """
            {"id":"launch-1","status":"preparing","message":"","performance_profile":"optimized","metal_hud":true,"network_debug":true,"wine_log":false,"progress":0.05,"logs":[],"started_at":"now","updated_at":"now"}
            """)
        }
        let body = StartGameLaunchRequest(
            installPath: "/tmp/game", performanceProfile: .optimized,
            metalHud: true, networkDebug: true, wineLog: false, framePacing: 120,
            credential: "stoken=fixture; mid=mid"
        )
        let launch: GameLaunch = try await client.post("/v1/game/launch", body: body)
        #expect(launch.status == .preparing)
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
