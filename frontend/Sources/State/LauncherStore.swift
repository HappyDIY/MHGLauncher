import Foundation
import Observation

@MainActor
@Observable
final class LauncherStore {
    let backend = BackendProcess()
    let keychain = KeychainStore()
    let deviceOwnerAuthenticator = DeviceOwnerAuthenticator()

    var account: Account?
    var roles: [GameRole] = []
    var gameState: GameState?
    var gameJob: GameJob?
    var wishes: [WishRecord] = []
    var wishStatistics: [WishStatistics] = []
    var dailyNote: DailyNote?
    var qrSession: QRSession?
    var noteVerification: GeetestChallenge?
    var installPath = ""
    var isBusy = false
    var message: String?
    var wishOperation: WishOperationState?

    let credentialAccount = "current"

    var selectedRole: GameRole? {
        roles.first(where: \.selected) ?? roles.first
    }

    var credential: String? {
        try? keychain.read(account: credentialAccount)
    }

    func bootstrap() async {
        await backend.start()
        guard backend.client != nil else {
            message = backend.errorMessage
            return
        }
        await refreshAccount()
        await refreshGame()
        if selectedRole != nil {
            await loadCompanionData()
        }
    }

    func perform(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch let error as APIErrorPayload {
            message = Self.presentableMessage(error.message)
        } catch {
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    nonisolated static func presentableMessage(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.allSatisfy(\.isNumber) else {
            return "操作失败，请稍后重试"
        }
        return normalized
    }

    func requireClient() throws -> APIClient {
        guard let client = backend.client else {
            throw LauncherError.backendUnavailable
        }
        return client
    }

    func requireCredential() throws -> String {
        guard let credential else { throw LauncherError.credentialMissing }
        return credential
    }
}

enum LauncherError: LocalizedError {
    case backendUnavailable
    case credentialMissing
    case roleMissing

    var errorDescription: String? {
        switch self {
        case .backendUnavailable: "本地服务不可用"
        case .credentialMissing: "请先登录米游社账号"
        case .roleMissing: "没有可用的原神角色"
        }
    }
}
