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

    @Test("解码后端生成的带小数秒时间")
    func decodeAccountWithFractionalSeconds() throws {
        let data = Data(
            """
            {
              "aid": "1001",
              "mid": "mid",
              "nickname": "旅行者",
              "credential_ref": "keychain:current",
              "updated_at": "2026-06-11T08:00:00.123456Z"
            }
            """.utf8
        )
        let account = try JSONDecoder.api.decode(Account.self, from: data)
        #expect(account.aid == "1001")
    }

    @Test("解码不带时区的祈愿时间")
    func decodeWishTimeWithoutTimeZone() throws {
        let data = Data(
            """
            {
              "id": "1001",
              "uid": "230289829",
              "gacha_type": "200",
              "item_id": "",
              "name": "笛剑",
              "item_type": "武器",
              "rank": 4,
              "time": "2026-05-26T13:50:30",
              "icon_url": "https://example.invalid/item.png"
            }
            """.utf8
        )
        let record = try JSONDecoder.api.decode(WishRecord.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))
        #expect(calendar.component(.hour, from: record.time) == 13)
        #expect(calendar.component(.minute, from: record.time) == 50)
        #expect(record.iconUrl?.lastPathComponent == "item.png")
    }

    @Test("未知祈愿图标允许为空")
    func decodeWishWithoutIcon() throws {
        let data = Data(
            """
            {
              "id": "1002",
              "uid": "230289829",
              "gacha_type": "301",
              "item_id": "unknown",
              "name": "未知物品",
              "item_type": "",
              "rank": 0,
              "time": "2026-05-26T13:50:30",
              "icon_url": null
            }
            """.utf8
        )
        let record = try JSONDecoder.api.decode(WishRecord.self, from: data)
        #expect(record.iconUrl == nil)
    }

    @Test("解码后端祈愿任务快照")
    func decodeWishTask() throws {
        let data = Data(
            """
            {
              "id": "task-1",
              "kind": "sync",
              "status": "running",
              "progress": null,
              "logs": [{
                "sequence": 1,
                "message": "已读取第 1 页：20 条记录，新增 20 条",
                "emphasized": false
              }],
              "result": null,
              "error": ""
            }
            """.utf8
        )
        let task = try JSONDecoder.api.decode(WishTaskSnapshot.self, from: data)
        #expect(task.progress == nil)
        #expect(task.logs.first?.sequence == 1)
        #expect(task.logs.first?.message.contains("20 条记录") == true)
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

    @Test("无意义错误消息使用可读提示")
    func presentableErrorMessage() {
        #expect(LauncherStore.presentableMessage("") == "操作失败，请稍后重试")
        #expect(LauncherStore.presentableMessage("2") == "操作失败，请稍后重试")
        #expect(LauncherStore.presentableMessage("登录失效") == "登录失效")
    }
}
