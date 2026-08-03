import Foundation

struct ProviderIdentity: Sendable {
    let aid: String
    let mid: String
    let nickname: String
    let credential: String
}

protocol GameProvider: Sendable {
    func createQRSession() async throws -> QRSession
    func queryQRSession(_ id: String) async throws -> (QRSession, ProviderIdentity?)
    func identifyCredential(_ credential: String) async throws -> ProviderIdentity
    func createMobileCaptcha(_ mobile: String) async throws -> MobileCaptchaSession
    func verifyMobileCaptcha(_ request: MobileCaptchaVerificationRequest) async throws -> MobileCaptchaSession
    func loginByMobileCaptcha(_ request: MobileLoginRequest) async throws -> ProviderIdentity
    func roles(credential: String) async throws -> [GameRole]
    func build(installedVersion: String, audioLanguages: [String]) async throws -> GameBuild
    func installedBuild(version: String, audioLanguages: [String]) async throws -> GameBuild
    func predownloadBuild(installedVersion: String, audioLanguages: [String]) async throws -> GameBuild?
    func gachaURL(credential: String, role: GameRole) async throws -> URL
    func wishes(
        credential: String,
        role: GameRole,
        newest: [String: String]
    ) -> AsyncThrowingStream<[WishRecord], Error>
    func wishes(gachaURL: URL) -> AsyncThrowingStream<[WishRecord], Error>
    func dailyNote(
        credential: String,
        role: GameRole,
        challenge: String,
        challengePath: String
    ) async throws -> DailyNote
    func verifyNoteChallenge(
        credential: String,
        challenge: String,
        validate: String,
        challengePath: String
    ) async throws -> String
    func authTicket(credential: String) async throws -> String
}
