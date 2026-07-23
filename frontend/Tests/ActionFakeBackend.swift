import Foundation
@testable import MHGLauncher

actor ActionFakeBackend {
    private(set) var requests: [APIRequest] = []
    private(set) var unexpectedRequests: [APIRequest] = []
    private var loggedOut = false
    private var speedLimit = 0

    func respond(_ request: APIRequest) async throws -> APIResponse {
        requests.append(request)
        let route = request.path.components(separatedBy: "?")[0]
        switch (request.method, route) {
        case ("GET", "/v1/accounts"): return try actionJSON(loggedOut ? [] : [InteractiveFixtures.account])
        case ("GET", "/v1/account"): return loggedOut ? null() : try actionJSON(InteractiveFixtures.account)
        case ("GET", "/v1/roles"): return try actionJSON(loggedOut ? [] : [InteractiveFixtures.role])
        case ("POST", "/v1/account/select"): return try actionJSON(selection())
        case ("POST", "/v1/roles/select"): return try actionJSON(InteractiveFixtures.role)
        case ("DELETE", "/v1/account"):
            loggedOut = true
            return empty()
        case ("POST", "/v1/auth/qr-sessions"): return try actionJSON(qr("created"))
        case ("GET", "/v1/auth/qr-sessions/qr-1"): return try actionJSON(qrResult())
        case ("POST", "/v1/auth/commit"): return try actionJSON(loginResponse())
        case ("POST", "/v1/auth/abort"): return empty()
        case ("POST", "/v1/auth/mobile-captcha"): return try actionJSON(mobileSession())
        case ("POST", "/v1/auth/mobile-captcha/verification"): return try actionJSON(mobileSession())
        case ("POST", "/v1/auth/mobile-login"): return try actionJSON(preparedLogin())
        case ("POST", "/v1/auth/cookie-login"): return try actionJSON(preparedLogin())
        case ("GET", "/v1/game/status"), ("GET", "/v1/game/status/path"):
            return try actionJSON(InteractiveFixtures.gameState)
        case ("GET", "/v1/game/space-check"):
            return try actionJSON(SpaceCheckResult(available: 9_999, required: 1, sufficient: true))
        case ("POST", "/v1/game/jobs"):
            let value = try JSONDecoder.api.decode(StartJobRequest.self, from: request.body ?? Data())
            return try actionJSON(gameJob(.running, kind: value.kind))
        case ("GET", "/v1/game/jobs/job-1"): return try actionJSON(gameJob(.completed))
        case ("POST", "/v1/game/jobs/job-1/control"): return try actionJSON(controlledJob(request))
        case ("GET", "/v1/settings/speed-limit"):
            return try actionJSON(SpeedLimitResponse(speedLimitKb: speedLimit))
        case ("POST", "/v1/settings/speed-limit"):
            speedLimit = try JSONDecoder.api.decode(SpeedLimitRequest.self, from: request.body ?? Data()).speedLimitKb
            return try actionJSON(SpeedLimitResponse(speedLimitKb: speedLimit))
        case ("POST", "/v1/game/launch"): return try actionJSON(gameLaunch(.running))
        case ("GET", "/v1/game/launches/launch-1"): return try actionJSON(gameLaunch(.stopped))
        case ("POST", "/v1/game/launches/launch-1/stop"): return try actionJSON(gameLaunch(.stopped))
        case ("POST", "/v1/notes/refresh"): return try actionJSON(InteractiveFixtures.dailyNote)
        case ("POST", "/v1/notes/verification"):
            return try actionJSON(NoteVerificationResponse(xrpcChallenge: "verified"))
        case ("GET", "/v1/companion/snapshot"):
            return try actionJSON(CompanionSnapshot(
                wishes: InteractiveFixtures.wishRecords,
                statistics: [InteractiveFixtures.wishStatistics],
                bannerStatistics: [InteractiveFixtures.bannerDetail],
                note: InteractiveFixtures.dailyNote
            ))
        case ("POST", "/v1/wishes/tasks/sync"): return try actionJSON(wishTask())
        case ("POST", "/v1/wishes/tasks/import"): return try actionJSON(wishTask())
        case ("GET", "/v1/wishes/tasks/task-1"): return try actionJSON(wishTask())
        case ("GET", "/v1/wishes"): return try actionJSON(InteractiveFixtures.wishRecords)
        case ("GET", "/v1/wishes/statistics"): return try actionJSON([InteractiveFixtures.wishStatistics])
        case ("GET", "/v1/wishes/banner-statistics"): return try actionJSON([InteractiveFixtures.bannerDetail])
        case ("GET", "/v1/notes"): return try actionJSON(Optional.some(InteractiveFixtures.dailyNote))
        case ("GET", "/v1/characters"): return try actionJSON([GameCharacter]())
        case ("GET", "/v1/notifications/settings"): return try actionJSON(actionNotificationSettings())
        case ("GET", "/v1/achievements/goals"): return try actionJSON([AchievementGoal]())
        case ("GET", "/v1/cloud/session"): return null()
        case ("GET", "/v1/achievements/archive"): return try actionJSON(actionAchievementArchive())
        case ("GET", "/v1/achievements/snapshot"): return try actionJSON(actionAchievementSnapshot())
        case ("GET", "/v1/wishes/export"): return APIResponse(status: 200, body: Data(#"{"uigf_version":"4.0","list":[]}"#.utf8))
        case ("DELETE", "/v1/wishes"):
            return try actionJSON(CountResponse(inserted: nil, imported: nil, deleted: 2, uploaded: nil))
        default:
            unexpectedRequests.append(request)
            throw ActionFakeBackendError.unexpected("\(request.method) \(request.path)")
        }
    }

    func saw(_ method: String, _ route: String) -> Bool {
        requests.contains { request in
            request.method == method
                && request.path.components(separatedBy: "?")[0] == route
        }
    }

    func startedJobKinds() throws -> [JobKind] {
        try requests.compactMap { request in
            guard request.method == "POST",
                  request.path.components(separatedBy: "?")[0] == "/v1/game/jobs" else {
                return nil
            }
            return try JSONDecoder.api.decode(StartJobRequest.self, from: request.body ?? Data()).kind
        }
    }
}

enum ActionFakeBackendError: Error {
    case unexpected(String)
}
