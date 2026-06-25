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
    let selected: Bool
    let updatedAt: Date

    func displayName(role: GameRole?) -> String {
        let accountName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let roleName = role?.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.nonempty ?? roleName?.nonempty ?? "米游社用户"
    }
}

struct GameRole: Codable, Sendable, Identifiable {
    var id: String { uid }
    let uid: String
    let nickname: String
    let region: String
    let level: Int
    let selected: Bool

    var regionName: String {
        switch region {
        case "cn_gf01": "天空岛服"
        case "cn_qd01": "世界树服"
        default: region.nonempty ?? "未知服务器"
        }
    }
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

struct AccountSelectionResponse: Codable {
    let account: Account
    let roles: [GameRole]
}
