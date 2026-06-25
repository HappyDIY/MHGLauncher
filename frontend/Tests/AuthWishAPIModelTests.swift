import Foundation
import Testing
@testable import MHGLauncher

@Suite("账号与祈愿 API 模型")
struct AuthWishAPIModelTests {
    @Test("解码祈愿限流错误码")
    func decodeWishTaskLimitedError() throws {
        let data = Data(
            """
            {
              "id": "task-1",
              "kind": "sync",
              "status": "failed",
              "progress": null,
              "logs": [],
              "result": null,
              "error": "visit too frequently",
              "error_code": "wish_sync_limited"
            }
            """.utf8
        )
        let task = try JSONDecoder.api.decode(WishTaskSnapshot.self, from: data)
        #expect(task.errorCode == "wish_sync_limited")
        #expect(task.failureMessage == "访问过于频繁，请稍后再同步祈愿记录")
    }

    @Test("解码短信验证上下文")
    func decodeMobileCaptchaVerification() throws {
        let data = Data(
            """
            {
              "mobile": "13800138000",
              "action_type": "login",
              "countdown": 60,
              "aigis": null,
              "verification": {
                "gt": "gt-token",
                "challenge": "server-challenge",
                "session_id": "risk-session"
              }
            }
            """.utf8
        )
        let session = try JSONDecoder.api.decode(MobileCaptchaSession.self, from: data)
        #expect(session.verification?.sessionId == "risk-session")
    }
}
