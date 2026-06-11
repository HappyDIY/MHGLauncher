import LocalAuthentication

@MainActor
struct DeviceOwnerAuthenticator {
    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        ) else {
            throw DeviceOwnerAuthenticationError.unavailable(
                error?.localizedDescription
            )
        }
        try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
    }
}

enum DeviceOwnerAuthenticationError: LocalizedError {
    case unavailable(String?)

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            detail ?? "此 Mac 未配置 Touch ID 或登录密码"
        }
    }
}
