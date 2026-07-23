import Foundation
import Testing
@testable import MHGLauncher

@Suite("本地 API 响应契约")
struct APIContractResponseTests {
    @Test("真实后端响应语料均可由 Swift 生产模型解码")
    func responsesDecodeWithProductionModels() throws {
        let corpus = try APIContractCorpus.load()
        for fixture in corpus.responses {
            let data = try contractData(fixture)
            switch fixture.model {
            case "api_error": _ = try JSONDecoder.api.decode(APIErrorPayload.self, from: data)
            case "account": _ = try JSONDecoder.api.decode(Account.self, from: data)
            case "game_state": _ = try JSONDecoder.api.decode(GameState.self, from: data)
            case "game_job": _ = try JSONDecoder.api.decode(GameJob.self, from: data)
            case "game_launch": _ = try JSONDecoder.api.decode(GameLaunch.self, from: data)
            case "wish_task": _ = try JSONDecoder.api.decode(WishTaskSnapshot.self, from: data)
            case "daily_note": _ = try JSONDecoder.api.decode(DailyNote.self, from: data)
            case "companion_snapshot":
                _ = try JSONDecoder.api.decode(CompanionSnapshot.self, from: data)
            default: Issue.record("未覆盖响应模型：\(fixture.model ?? "nil")")
            }
        }
    }

    @Test("错误详情完整保留混合 JSON 类型")
    func errorDetailsPreserveMixedValues() throws {
        let fixture = try APIContractCorpus.load().response(named: "api_error")
        let payload = try JSONDecoder.api.decode(APIErrorPayload.self, from: contractData(fixture))

        #expect(payload.details?["required"]?.integerValue == 130)
        #expect(payload.details?["sufficient"]?.boolValue == false)
        #expect(payload.details?["hint"] == .null)
        #expect(payload.details?["causes"] == .array([.string("download"), .string("install")]))
    }

    @Test("未知响应枚举会使边界测试失败")
    func unknownEnumIsRejected() throws {
        let fixture = try APIContractCorpus.load().response(named: "game_job")
        guard case .object(var body) = fixture.body else {
            Issue.record("game_job 不是对象")
            return
        }
        body["status"] = .string("finished")
        let data = try JSONEncoder().encode(JSONValue.object(body))
        #expect(throws: DecodingError.self) {
            try JSONDecoder.api.decode(GameJob.self, from: data)
        }
    }
}
