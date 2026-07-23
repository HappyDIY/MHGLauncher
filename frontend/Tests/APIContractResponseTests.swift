import Foundation
import Testing
@testable import MHGLauncher

@Suite("本地 API 响应契约")
struct APIContractResponseTests {
    @Test("响应顶层字段名严格匹配")
    func responseKeysMatchContract() throws {
        for fixture in try APIContractCorpus.load().responses {
            guard let model = fixture.model,
                  case .object(let body) = fixture.body else {
                Issue.record("响应语料缺少对象模型：\(fixture.name)")
                continue
            }
            #expect(Set(body.keys) == expectedResponseKeys(model), "响应字段漂移：\(fixture.name)")
        }
    }

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

private func expectedResponseKeys(_ model: String) -> Set<String> {
    switch model {
    case "api_error": ["code", "message", "details"]
    case "account": ["aid", "mid", "nickname", "credential_ref", "selected", "updated_at"]
    case "game_state": [
        "install_path", "installed_version", "available_version", "status", "update_kind",
        "download_bytes", "predownload_version", "predownload_finished",
    ]
    case "game_job": [
        "id", "kind", "status", "completed_bytes", "total_bytes", "message", "download_speed",
        "chunks_completed", "chunks_total", "active_chunks", "last_update", "revision",
    ]
    case "game_launch": [
        "id", "status", "message", "performance_profile", "metal_hud", "network_debug",
        "wine_log", "progress", "logs", "started_at", "updated_at", "revision",
    ]
    case "wish_task": [
        "id", "kind", "status", "progress", "logs", "result", "error", "revision", "target_uids",
    ]
    case "daily_note": [
        "uid", "current_resin", "max_resin", "finished_tasks", "total_tasks",
        "extra_task_reward_received", "expeditions_finished", "expeditions_total",
        "current_home_coin", "max_home_coin", "weekly_boss_remaining", "transformer_ready",
        "refreshed_at",
    ]
    case "companion_snapshot": ["wishes", "statistics", "banner_statistics", "note"]
    default: []
    }
}
