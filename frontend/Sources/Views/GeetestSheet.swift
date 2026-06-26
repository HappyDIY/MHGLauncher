import SwiftUI

enum GeetestSheet: Identifiable {
    case note(GeetestChallenge)
    case mobile(MobileCaptchaVerificationContext)

    var id: String {
        switch self {
        case .note(let challenge): "note-\(challenge.id)"
        case .mobile(let verification): "mobile-\(verification.id)"
        }
    }

    var challenge: GeetestChallenge {
        switch self {
        case .note(let challenge): challenge
        case .mobile(let verification): verification.geetest
        }
    }

    var subtitle: String {
        switch self {
        case .note: "完成验证后将自动刷新实时便笺"
        case .mobile: "完成验证后将自动发送短信验证码"
        }
    }
}
