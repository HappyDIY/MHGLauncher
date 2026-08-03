import Foundation
import SwiftUI

struct LauncherClient: @unchecked Sendable {
    let accounts: AccountClient
    let game: GameClient
    let companion: CompanionClient
    let resources: ResourceClient
    let achievements: AchievementClient
    let cloud: CloudClient
    let notifications: NotificationClient
    let updates: UpdateClient
    let images: ImageClient
}

struct AccountClient: @unchecked Sendable {
    var list: () async throws -> [Account]
    var selected: () async throws -> Account?
    var roles: () async throws -> [GameRole]
    var createQRSession: () async throws -> QRSession
    var queryQRSession: (String) async throws -> QRResult
    var sendMobileCaptcha: (String) async throws -> MobileCaptchaSession
    var verifyMobileCaptcha: (MobileCaptchaVerificationRequest) async throws -> MobileCaptchaSession
    var prepareMobileLogin: (MobileLoginRequest) async throws -> PreparedLogin
    var prepareCookieLogin: (String) async throws -> PreparedLogin
    var commitLogin: (String) async throws -> LoginCompleteResponse
    var abortLogin: (String) async -> Void
    var logout: () async throws -> Void
    var selectAccount: (String) async throws -> AccountSelectionResponse
    var selectRole: (String) async throws -> GameRole
}

struct GameClient: @unchecked Sendable {
    var status: (String?) async throws -> GameState
    var spaceCheck: (String, JobKind) async throws -> SpaceCheckResult
    var startJob: (JobKind, String) async throws -> GameJob
    var jobEvents: (String, Int?) -> AsyncThrowingStream<GameJob, Error>
    var controlJob: (String, String) async throws -> GameJob
    var speedLimit: () async throws -> Int
    var setSpeedLimit: (Int) async throws -> Int
    var launch: (StartGameLaunchRequest) async throws -> GameLaunch
    var launchEvents: (String, Int?) -> AsyncThrowingStream<GameLaunch, Error>
    var stopLaunch: (String) async throws -> GameLaunch
    var runWineTool: (WineToolRequest) async throws -> Void
}

struct CompanionClient: @unchecked Sendable {
    var snapshot: (String) async throws -> CompanionSnapshot
    var startWishSync: () async throws -> WishTaskSnapshot
    var importUIGF: (Data) async throws -> WishTaskSnapshot
    var importGachaURL: (String) async throws -> WishTaskSnapshot
    var wishTaskEvents: (String, Int?) -> AsyncThrowingStream<WishTaskSnapshot, Error>
    var exportUIGF: (String) async throws -> Data
    var clearWishes: () async throws -> Int
    var refreshNote: (NoteRefreshRequest) async throws -> DailyNote
    var verifyNote: (NoteVerificationRequest) async throws -> NoteVerificationResponse
    var characters: (String) async throws -> [GameCharacter]
    var refreshCharacters: () async throws -> [GameCharacter]
    var refreshCharacter: (String) async throws -> GameCharacter
    var cacheCharacterAssets: () async throws -> [GameCharacter]
}

struct ResourceClient: @unchecked Sendable {
    var status: () async throws -> ResourceSyncStatus
    var sync: (Bool) async throws -> ResourceSyncStatus
    var gachaStatus: () async throws -> GachaResourceStatus
    var gachaEvents: () async throws -> [GachaEvent]
}

struct AchievementClient: @unchecked Sendable {
    var archive: (String) async throws -> AchievementArchive
    var snapshot: (String) async throws -> AchievementSnapshot
    var goals: () async throws -> [AchievementGoal]
    var importUIAF: (Data, String, Int) async throws -> AchievementSnapshot
    var exportUIAF: (String) async throws -> Data
    var save: (AchievementSaveRequest) async throws -> AchievementSnapshot
}

struct CloudClient: @unchecked Sendable {
    var session: (String) async throws -> CloudSession?
    var login: () async throws -> CloudLoginResult
    var uploadWishes: (String) async throws -> Int
    var retrieveWishes: (String) async throws -> Int
    var uploadAchievements: (String) async throws -> Int
    var retrieveAchievements: (String) async throws -> Int
}

struct NotificationClient: @unchecked Sendable {
    var settings: () async throws -> NotificationSettings
    var updateSettings: (NotificationSettings) async throws -> NotificationSettings
    var evaluate: (String?) async throws -> [NotificationEvent]
    var acknowledge: ([String]) async throws -> [String]
}

struct UpdateClient: @unchecked Sendable {
    var manifest: () async throws -> AppUpdateManifest
}

struct ImageClient: @unchecked Sendable {
    var load: (URL) async throws -> Data
}

struct MHGResourceURL: Hashable, Sendable {
    static let scheme = "mhg-resource"
    let url: URL

    init(_ url: URL) throws {
        guard url.scheme == Self.scheme,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil,
              !url.pathComponents.contains("..") else {
            throw LauncherCoreError(code: "invalid_resource_url", message: "资源地址无效")
        }
        self.url = url
    }
}

struct LauncherCoreError: Codable, Error, LocalizedError, Sendable {
    let code: String
    let message: String
    let details: [String: JSONValue]?

    init(code: String, message: String, details: [String: JSONValue]? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }

    var errorDescription: String? { message }
}

private struct LauncherClientKey: EnvironmentKey {
    static let defaultValue: LauncherClient? = nil
}

extension EnvironmentValues {
    var launcherClient: LauncherClient? {
        get { self[LauncherClientKey.self] }
        set { self[LauncherClientKey.self] = newValue }
    }
}
