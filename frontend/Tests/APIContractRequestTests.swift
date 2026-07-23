import Foundation
import Testing
@testable import MHGLauncher

@Suite("本地 API 请求契约")
struct APIContractRequestTests {
    @Test("Swift 请求编码与已提交语料严格一致")
    func requestsMatchCorpus() throws {
        let corpus = try APIContractCorpus.load()
        let installPath = "/Games/Genshin Impact Game"
        let requests: [(String, any Encodable)] = [
            ("install_job", StartJobRequest(kind: .install, installPath: installPath)),
            ("update_job", StartJobRequest(kind: .update, installPath: installPath)),
            ("predownload_job", StartJobRequest(kind: .predownload, installPath: installPath)),
            ("control_job", ControlJobRequest(action: "pause")),
            ("speed_limit", SpeedLimitRequest(speedLimitKb: 2048)),
            ("start_launch", StartGameLaunchRequest(
                installPath: installPath,
                performanceProfile: .optimized,
                metalHud: true,
                networkDebug: false,
                wineLog: false,
                framePacing: 120,
                credential: "stoken=fixture; mid=mid"
            )),
            ("login_transaction", LoginCommitRequest(
                transactionId: "00000000-0000-4000-8000-000000000001"
            )),
            ("note_refresh", NoteRefreshRequest(
                credential: "stoken=fixture",
                xrpcChallenge: "",
                xrpcChallengePath: ""
            )),
            ("notification_settings", NotificationSettings(
                dailyCommissionEnabled: true,
                dailyCommissionTime: "08:00",
                resinFullEnabled: true,
                gachaRefreshEnabled: true,
                versionUpdateEnabled: true
            )),
            ("notification_acknowledgement", NotificationAcknowledgement(
                keys: ["daily:100000001:2026-07-24"]
            )),
            ("achievement_save", AchievementSaveRequest(
                archiveId: "100000001",
                expectedRevision: 0,
                items: [AchievementItemInput(
                    achievementId: 84501,
                    current: 1,
                    status: 3,
                    timestamp: 1_756_000_000
                )]
            )),
            ("cloud_uid", CloudUIDRequest(uid: "100000001", token: "fixture-token")),
        ]

        #expect(corpus.version == 1)
        #expect(requests.count == corpus.requests.count)
        for (name, request) in requests {
            let expected = try contractJSONObject(corpus.request(named: name))
            let actual = try existentialJSONObject(request)
            #expect(actual == expected, "请求语料不一致：\(name)")
        }
    }
}

private func existentialJSONObject(_ value: any Encodable) throws -> NSDictionary {
    try contractJSONObject(AnyEncodable(value))
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}
