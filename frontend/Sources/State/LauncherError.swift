import Foundation

enum LauncherError: LocalizedError, Equatable {
    case coreUnavailable
    case credentialMissing
    case loginExpired
    case roleMissing

    var errorDescription: String? {
        switch self {
        case .coreUnavailable: "Launcher Core 不可用"
        case .credentialMissing: "请先登录米游社账号"
        case .loginExpired: "登录确认已过期，请重新登录"
        case .roleMissing: "没有可用的原神角色"
        }
    }
}
