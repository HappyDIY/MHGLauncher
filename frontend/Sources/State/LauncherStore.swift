import Foundation
import Observation

@MainActor
@Observable
final class LauncherStore {
    let backend = BackendProcess()
    let runtimeInstaller = RuntimeInstaller()
    let keychain = KeychainStore()
    let deviceOwnerAuthenticator = DeviceOwnerAuthenticator()
    var value = ValueStore()
    var runtimeProgress: RuntimeProgress?
    var runtimeErrorMessage: String?
    var isBootstrapping = false
    var isInstallingCoreRuntime = false
    var isInstallingGameRuntime = false
    var gameRuntimeReady = false
    private var installedRuntime: InstalledRuntime?
    var account: Account?
    var accounts: [Account] = []
    var roles: [GameRole] = []
    var gameState: GameState?
    var gameJob: GameJob?
    var pendingGameJobKind: JobKind?
    var gameLaunch: GameLaunch?
    var isLaunchingGame = false
    var isStoppingGame = false
    var gamePerformanceProfile = GamePerformanceProfile(
        rawValue: UserDefaults.standard.string(forKey: "gamePerformanceProfile") ?? ""
    ) ?? .optimized {
        didSet { UserDefaults.standard.set(gamePerformanceProfile.rawValue, forKey: "gamePerformanceProfile") }
    }
    var metalHudEnabled = UserDefaults.standard.bool(forKey: "metalHudEnabled") {
        didSet { UserDefaults.standard.set(metalHudEnabled, forKey: "metalHudEnabled") }
    }
    var networkDebugEnabled = UserDefaults.standard.bool(forKey: "networkDebugEnabled") {
        didSet { UserDefaults.standard.set(networkDebugEnabled, forKey: "networkDebugEnabled") }
    }
    var wineLogEnabled = UserDefaults.standard.bool(forKey: "wineLogEnabled") {
        didSet { UserDefaults.standard.set(wineLogEnabled, forKey: "wineLogEnabled") }
    }
    var wishes: [WishRecord] = []
    var wishStatistics: [WishStatistics] = []
    var bannerDetails: [WishBannerDetail] = []
    var dailyNote: DailyNote?
    var qrSession: QRSession?
    var mobileCaptchaSession: MobileCaptchaSession?
    var mobileCaptchaVerification: MobileCaptchaVerificationContext?
    var loginMobile = ""
    var loginCaptcha = ""
    var loginCookie = ""
    var noteVerification: GeetestChallenge?
    var loginFormPresented = false
    var selectedDestination: Destination? = .home
    var installPath = ""
    var isBusy = false
    var companionLoaded = false
    var message: String?
    var statusMessage: String?; var statusMessageRevision = 0
    var wishOperation: WishOperationState?
    var triggerWishImport = false
    var triggerWishExport = false
    var triggerWishClear = false
    var showsLoginBeforeLaunch = false
    var speedLimitKB = 0
    let loginDeferralKey = "loginLaunchDeferrals"
    var qrLoginAttempt = 0
    var selectedRole: GameRole? {
        roles.first(where: \.selected) ?? roles.first
    }
    var credential: String? {
        guard let account else { return nil }
        return try? keychain.read(account: keychainAccount(for: account.aid))
    }

    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            let hasInstalledCore = runtimeInstaller.installedCoreRuntime() != nil
            if !hasInstalledCore {
                isInstallingCoreRuntime = true
            }
            let runtime = try await runtimeInstaller.ensureCore { progress in
                self.runtimeProgress = progress
            }
            installedRuntime = runtime
            gameRuntimeReady = runtimeInstaller.isGameInstalled()
            runtimeErrorMessage = nil
            isInstallingCoreRuntime = false
            await backend.start(runtime: runtime)
        } catch {
            isInstallingCoreRuntime = false
            runtimeErrorMessage = Self.presentableMessage(error.localizedDescription)
            message = runtimeErrorMessage
            return
        }
        guard backend.client != nil else {
            message = backend.errorMessage
            return
        }
        await refreshAccount()
        await refreshGame()
        await refreshSpeedLimit()
        let savedKB = UserDefaults.standard.integer(forKey: "downloadSpeedLimitKB")
        if savedKB > 0 { await setSpeedLimit(savedKB) }
        if selectedRole != nil {
            await loadCompanionData()
            await loadValueData()
        }
    }

    func retryBootstrap() async {
        backend.stop()
        runtimeProgress = nil
        await bootstrap()
    }

    func checkGameRuntime() {
        gameRuntimeReady = runtimeInstaller.isGameInstalled()
    }

    func ensureGameRuntime() async throws {
        if gameRuntimeReady { return }
        isInstallingGameRuntime = true
        defer { isInstallingGameRuntime = false }
        let runtime = try await runtimeInstaller.ensureGame { progress in
            self.runtimeProgress = progress
        }
        installedRuntime = runtime
        gameRuntimeReady = true
        runtimeErrorMessage = nil
    }

    func perform(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
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

    func requireLaunchCredential() throws -> String? {
        guard let account else { return nil }
        guard let credential = try keychain.read(account: keychainAccount(for: account.aid)) else {
            throw LauncherError.credentialMissing
        }
        return credential
    }

    func keychainAccount(for aid: String) -> String {
        "account:\(aid)"
    }
}

enum LauncherError: LocalizedError, Equatable {
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
