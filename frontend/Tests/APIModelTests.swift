import Foundation
import Testing
@testable import MHGLauncher

@Suite("API 模型")
struct APIModelTests {
    @Test("解码账号蛇形字段与 ISO 时间")
    func decodeAccount() throws {
        let data = Data(
            """
            {
              "aid": "1001",
              "mid": "mid",
              "nickname": "旅行者",
              "credential_ref": "keychain:current",
              "updated_at": "2026-06-11T08:00:00Z"
            }
            """.utf8
        )
        let account = try JSONDecoder.api.decode(Account.self, from: data)
        #expect(account.nickname == "旅行者")
        #expect(account.credentialRef == "keychain:current")
    }

    @Test("解码统一错误")
    func decodeError() throws {
        let data = Data(
            """
            {
              "code": "launch_not_implemented",
              "message": "游戏启动功能尚未实现",
              "details": {}
            }
            """.utf8
        )
        let error = try JSONDecoder.api.decode(APIErrorPayload.self, from: data)
        #expect(error.code == "launch_not_implemented")
    }

    @Test("编码请求使用蛇形字段")
    func encodeStartJob() throws {
        let request = StartJobRequest(kind: .install, installPath: "/tmp/game")
        let data = try JSONEncoder.api.encode(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        #expect(object["install_path"] == "/tmp/game")
    }

    @Test("账号空昵称使用角色昵称")
    func accountDisplayName() {
        let account = Account(
            aid: "1001",
            mid: "mid",
            nickname: "  ",
            credentialRef: "keychain:current",
            updatedAt: .now
        )
        let role = GameRole(
            uid: "100000001",
            nickname: "旅行者",
            region: "cn_gf01",
            level: 60,
            selected: true
        )
        #expect(account.displayName(role: role) == "旅行者")
        #expect(role.regionName == "天空岛服")
    }
}
