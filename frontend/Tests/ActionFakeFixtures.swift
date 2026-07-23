import Foundation
@testable import MHGLauncher

func actionJSON<T: Encodable>(_ value: T) throws -> APIResponse {
    APIResponse(status: 200, body: try JSONEncoder.api.encode(value))
}

func null() -> APIResponse {
    APIResponse(status: 200, body: Data("null".utf8))
}

func empty() -> APIResponse {
    APIResponse(status: 200, body: Data("{}".utf8))
}

func selection() -> AccountSelectionResponse {
    AccountSelectionResponse(
        account: InteractiveFixtures.account,
        roles: [InteractiveFixtures.role]
    )
}

func loginResponse() -> LoginCompleteResponse {
    LoginCompleteResponse(
        account: InteractiveFixtures.account,
        roles: [InteractiveFixtures.role]
    )
}

func qr(_ status: String) -> QRSession {
    QRSession(
        id: "qr-1",
        url: "https://example.invalid/qr",
        status: status,
        expiresAt: .now.addingTimeInterval(300)
    )
}

func qrResult() -> QRResult {
    QRResult(
        session: qr("confirmed"),
        preparedLogin: preparedLogin()
    )
}

func preparedLogin() -> PreparedLogin {
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

func mobileSession() -> MobileCaptchaSession {
    MobileCaptchaSession(
        mobile: "13800138000",
        actionType: "login",
        countdown: 60,
        aigis: nil,
        verification: nil
    )
}

func gameJob(_ status: JobStatus, kind: JobKind = .update) -> GameJob {
    GameJob(
        id: "job-1",
        kind: kind,
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

func controlledJob(_ request: APIRequest) throws -> GameJob {
    let action = try JSONDecoder.api.decode(
        ControlJobRequest.self,
        from: request.body ?? Data()
    ).action
    return gameJob(action == "pause" ? .paused : action == "cancel" ? .cancelled : .running)
}

func gameLaunch(_ status: GameLaunchStatus) -> GameLaunch {
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

func wishTask() -> WishTaskSnapshot {
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

func actionNotificationSettings() -> NotificationSettings {
    NotificationSettings(
        dailyCommissionEnabled: true,
        dailyCommissionTime: "08:00",
        resinFullEnabled: true,
        gachaRefreshEnabled: true,
        versionUpdateEnabled: true
    )
}

func actionAchievementArchive() -> AchievementArchive {
    AchievementArchive(
        id: InteractiveFixtures.role.uid,
        name: InteractiveFixtures.role.uid,
        selected: true,
        createdAt: .now,
        updatedAt: .now,
        revision: 0
    )
}

func actionAchievementSnapshot() -> AchievementSnapshot {
    AchievementSnapshot(
        archive: actionAchievementArchive(),
        entries: [],
        revision: 0
    )
}
