import Foundation
@testable import MHGLauncher

actor ActionFakeBackend {
    private(set) var requests: [APIRequest] = []
    private var loggedOut = false
    private var speedLimit = 0

    func respond(_ request: APIRequest) async throws -> APIResponse {
        requests.append(request)
        let route = request.path.components(separatedBy: "?")[0]
        switch (request.method, route) {
        case ("GET", "/v1/accounts"): return try json(loggedOut ? [] : [InteractiveFixtures.account])
        case ("GET", "/v1/account"): return loggedOut ? null() : try json(InteractiveFixtures.account)
        case ("GET", "/v1/roles"): return try json(loggedOut ? [] : [InteractiveFixtures.role])
        case ("POST", "/v1/account/select"): return try json(selection())
        case ("POST", "/v1/roles/select"): return try json(InteractiveFixtures.role)
        case ("DELETE", "/v1/account"):
            loggedOut = true
            return empty()
        case ("POST", "/v1/auth/qr-sessions"): return try json(qr("created"))
        case ("GET", "/v1/auth/qr-sessions/qr-1"): return try json(qrResult())
        case ("POST", "/v1/auth/commit"): return try json(loginResponse())
        case ("POST", "/v1/auth/abort"): return empty()
        case ("POST", "/v1/auth/mobile-captcha"): return try json(mobileSession())
        case ("POST", "/v1/auth/mobile-captcha/verification"): return try json(mobileSession())
        case ("POST", "/v1/auth/mobile-login"): return try json(preparedLogin())
        case ("POST", "/v1/auth/cookie-login"): return try json(preparedLogin())
        case ("GET", "/v1/game/status"), ("GET", "/v1/game/status/path"):
            return try json(InteractiveFixtures.gameState)
        case ("GET", "/v1/game/space-check"):
            return try json(SpaceCheckResult(available: 9_999, required: 1, sufficient: true))
        case ("POST", "/v1/game/jobs"): return try json(gameJob(.running))
        case ("GET", "/v1/game/jobs/job-1"): return try json(gameJob(.completed))
        case ("POST", "/v1/game/jobs/job-1/control"): return try json(controlledJob(request))
        case ("GET", "/v1/settings/speed-limit"):
            return try json(SpeedLimitResponse(speedLimitKb: speedLimit))
        case ("POST", "/v1/settings/speed-limit"):
            speedLimit = try JSONDecoder.api.decode(SpeedLimitRequest.self, from: request.body ?? Data()).speedLimitKb
            return try json(SpeedLimitResponse(speedLimitKb: speedLimit))
        case ("POST", "/v1/game/launch"): return try json(gameLaunch(.running))
        case ("GET", "/v1/game/launches/launch-1"): return try json(gameLaunch(.stopped))
        case ("POST", "/v1/game/launches/launch-1/stop"): return try json(gameLaunch(.stopped))
        case ("POST", "/v1/notes/refresh"): return try json(InteractiveFixtures.dailyNote)
        case ("POST", "/v1/notes/verification"):
            return try json(NoteVerificationResponse(xrpcChallenge: "verified"))
        case ("GET", "/v1/companion/snapshot"):
            return try json(CompanionSnapshot(
                wishes: InteractiveFixtures.wishRecords,
                statistics: [InteractiveFixtures.wishStatistics],
                bannerStatistics: [InteractiveFixtures.bannerDetail],
                note: InteractiveFixtures.dailyNote
            ))
        case ("POST", "/v1/wishes/tasks/sync"): return try json(wishTask())
        case ("POST", "/v1/wishes/tasks/import"): return try json(wishTask())
        case ("GET", "/v1/wishes/tasks/task-1"): return try json(wishTask())
        case ("GET", "/v1/wishes"): return try json(InteractiveFixtures.wishRecords)
        case ("GET", "/v1/wishes/statistics"): return try json([InteractiveFixtures.wishStatistics])
        case ("GET", "/v1/wishes/banner-statistics"): return try json([InteractiveFixtures.bannerDetail])
        case ("GET", "/v1/notes"): return try json(Optional.some(InteractiveFixtures.dailyNote))
        case ("GET", "/v1/wishes/export"): return APIResponse(status: 200, body: Data(#"{"uigf_version":"4.0","list":[]}"#.utf8))
        case ("DELETE", "/v1/wishes"):
            return try json(CountResponse(inserted: nil, imported: nil, deleted: 2, uploaded: nil))
        default:
            return APIResponse(status: 500, body: Data(#"{"code":"missing","message":"missing route","details":null}"#.utf8))
        }
    }

    func saw(_ method: String, _ route: String) -> Bool {
        requests.contains { request in
            request.method == method
                && request.path.components(separatedBy: "?")[0] == route
        }
    }
}

private func json<T: Encodable>(_ value: T) throws -> APIResponse {
    APIResponse(status: 200, body: try JSONEncoder.api.encode(value))
}

private func null() -> APIResponse {
    APIResponse(status: 200, body: Data("null".utf8))
}

private func empty() -> APIResponse {
    APIResponse(status: 200, body: Data("{}".utf8))
}

private func selection() -> AccountSelectionResponse {
    AccountSelectionResponse(
        account: InteractiveFixtures.account,
        roles: [InteractiveFixtures.role]
    )
}

private func loginResponse() -> LoginCompleteResponse {
    LoginCompleteResponse(
        account: InteractiveFixtures.account,
        roles: [InteractiveFixtures.role]
    )
}

private func qr(_ status: String) -> QRSession {
    QRSession(
        id: "qr-1",
        url: "https://example.invalid/qr",
        status: status,
        expiresAt: .now.addingTimeInterval(300)
    )
}

private func qrResult() -> QRResult {
    QRResult(
        session: qr("confirmed"),
        preparedLogin: preparedLogin()
    )
}

private func preparedLogin() -> PreparedLogin {
    PreparedLogin(
        transactionId: "00000000-0000-4000-8000-000000000001",
        identity: AccountIdentity(
            aid: InteractiveFixtures.account.aid,
            mid: InteractiveFixtures.account.mid,
            nickname: InteractiveFixtures.account.nickname,
            credential: "stoken=qr; mid=mid"
        ),
        roles: [InteractiveFixtures.role],
        expiresAt: .now.addingTimeInterval(300)
    )
}

private func mobileSession() -> MobileCaptchaSession {
    MobileCaptchaSession(
        mobile: "13800138000",
        actionType: "login",
        countdown: 60,
        aigis: nil,
        verification: nil
    )
}

private func gameJob(_ status: JobStatus) -> GameJob {
    GameJob(
        id: "job-1",
        kind: .update,
        status: status,
        completedBytes: status == .completed ? 1024 : 512,
        totalBytes: 1024,
        message: "",
        downloadSpeed: 128,
        chunksCompleted: status == .completed ? 2 : 1,
        chunksTotal: 2,
        activeChunks: [],
        lastUpdate: "2026-07-06T00:00:00Z",
        revision: 1
    )
}

private func controlledJob(_ request: APIRequest) throws -> GameJob {
    let action = try JSONDecoder.api.decode(ControlJobRequest.self, from: request.body ?? Data()).action
    return gameJob(action == "pause" ? .paused : action == "cancel" ? .cancelled : .running)
}

private func gameLaunch(_ status: GameLaunchStatus) -> GameLaunch {
    GameLaunch(
        id: "launch-1",
        status: status,
        message: "",
        performanceProfile: .optimized,
        metalHud: false,
        networkDebug: false,
        wineLog: false,
        progress: status == .stopped ? 1 : 0.5,
        logs: [],
        startedAt: "2026-07-06T00:00:00Z",
        updatedAt: "2026-07-06T00:00:01Z",
        revision: 1
    )
}

private func wishTask() -> WishTaskSnapshot {
    WishTaskSnapshot(
        id: "task-1",
        kind: "sync",
        status: .completed,
        progress: 1,
        logs: [WishTaskLogPayload(sequence: 1, message: "完成", emphasized: true)],
        result: ["inserted": 0],
        error: "",
        errorCode: nil,
        revision: 1,
        targetUids: nil
    )
}
