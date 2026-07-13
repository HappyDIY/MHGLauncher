import Foundation

struct APIErrorPayload: Decodable, Error {
    let code: String
    let message: String
    let details: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        details = try? container.decode([String: String].self, forKey: .details)
    }
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

struct MobileCaptchaSession: Codable, Sendable {
    let mobile: String
    let actionType: String
    let countdown: Int
    let aigis: String?
    let verification: MobileCaptchaVerification?
}

struct MobileCaptchaVerification: Codable, Sendable {
    let gt: String
    let challenge: String
    let sessionId: String
}

struct MobileCaptchaVerificationContext: Identifiable, Sendable {
    var id: String { verification.sessionId }
    let mobile: String
    let verification: MobileCaptchaVerification

    var geetest: GeetestChallenge {
        GeetestChallenge(gt: verification.gt, challenge: verification.challenge)
    }
}

struct QRResult: Codable, Sendable {
    let session: QRSession
    let preparedLogin: PreparedLogin?
}

struct PreparedLogin: Codable, Sendable {
    let transactionId: String
    let identity: AccountIdentity
    let roles: [GameRole]
    let expiresAt: Date
}

struct LoginCompleteResponse: Codable {
    let account: Account
    let roles: [GameRole]
}

struct LoginCommitRequest: Codable { let transactionId: String }

struct AccountSelectionResponse: Codable {
    let account: Account
    let roles: [GameRole]
}

struct MobileCaptchaRequest: Codable {
    let mobile: String
}

struct MobileCaptchaVerificationRequest: Codable, Sendable {
    let mobile: String
    let sessionId: String
    let challenge: String
    let validate: String
}

struct MobileLoginRequest: Codable {
    let mobile: String
    let captcha: String
    let actionType: String
    let aigis: String?
}

struct CookieLoginRequest: Codable {
    let credential: String
}
