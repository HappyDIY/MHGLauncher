import Foundation

struct APIErrorPayload: Codable, Error {
    let code: String
    let message: String
    let details: [String: String]?
}

struct Account: Codable, Sendable {
    let aid: String
    let mid: String
    let nickname: String
    let credentialRef: String
    let updatedAt: Date
}

struct GameRole: Codable, Sendable, Identifiable {
    var id: String { uid }
    let uid: String
    let nickname: String
    let region: String
    let level: Int
    let selected: Bool
}

struct QRSession: Codable, Sendable {
    let id: String
    let url: String
    let status: String
    let expiresAt: Date
}

struct AccountIdentity: Codable, Sendable {
    let aid: String
    let mid: String
    let nickname: String
    let credential: String
}

struct QRResult: Codable, Sendable {
    let session: QRSession
    let identity: AccountIdentity?
}

struct LoginCompleteRequest: Codable {
    let identity: AccountIdentity
    let credentialRef: String
}

struct LoginCompleteResponse: Codable {
    let account: Account
    let roles: [GameRole]
}

