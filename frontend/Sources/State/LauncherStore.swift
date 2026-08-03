import Foundation
import Observation
@MainActor
@Observable
final class LauncherStore {
    let coreHost: LauncherCoreHost
    let runtimeInstaller: RuntimeInstaller
    let userSettings: UserDefaults
    let notifications: any UserNotificationDelivering
    let clock: any LauncherClock
    let deviceOwnerAuthenticator: any DeviceOwnerAuthenticating
    var value = ValueStore()
    let appUpdate = AppUpdateState()
    init(
        dependencies: LauncherDependencies = LauncherDependencies(),
        deviceOwnerAuthenticator: any DeviceOwnerAuthenticating = DeviceOwnerAuthenticator()
    ) {
        coreHost = dependencies.coreHost; runtimeInstaller = dependencies.runtimeInstaller
        userSettings = dependencies.userSettings
        notifications = dependencies.notifications; clock = dependencies.clock
        isInstallingCoreRuntime = false
        self.deviceOwnerAuthenticator = deviceOwnerAuthenticator
        gamePerformanceProfile = GamePerformanceProfile(
            rawValue: dependencies.userSettings.string(forKey: "gamePerformanceProfile") ?? ""
        ) ?? .optimized
        metalHudEnabled = dependencies.userSettings.bool(forKey: "metalHudEnabled")
        networkDebugEnabled = dependencies.userSettings.bool(forKey: "networkDebugEnabled")
        wineLogEnabled = dependencies.userSettings.bool(forKey: "wineLogEnabled"); gameLaunchArguments = dependencies.userSettings.string(forKey: "gameLaunchArguments") ?? ""
    }
    var runtimeProgress: RuntimeProgress?; var runtimeErrorMessage: String?
    var isBootstrapping = false; var isInstallingCoreRuntime = false
    var isInstallingGameRuntime = false; var gameRuntimeReady = false
    private var installedRuntime: InstalledRuntime?
    var account: Account?
    var accounts: [Account] = []; var roles: [GameRole] = []
    var gameState: GameState?
    let gameJobPresentation = GameJobPresentation(); var gameJob: GameJob? { didSet { gameJobPresentation.apply(gameJob) } }
    var pendingGameJobKind: JobKind?; var gameLaunch: GameLaunch?
    @ObservationIgnored var gameStateIntent = 0
    @ObservationIgnored var gameJobIntent = 0
    @ObservationIgnored var gameLaunchIntent = 0
    @ObservationIgnored var launchPollingTask: Task<Void, Never>?
    var isLaunchingGame = false; var isStoppingGame = false
    var gamePerformanceProfile: GamePerformanceProfile { didSet {
        userSettings.set(gamePerformanceProfile.rawValue, forKey: "gamePerformanceProfile")
    } }
    var metalHudEnabled: Bool { didSet { userSettings.set(metalHudEnabled, forKey: "metalHudEnabled") } }
    var networkDebugEnabled: Bool { didSet { userSettings.set(networkDebugEnabled, forKey: "networkDebugEnabled") } }
    var wineLogEnabled: Bool { didSet { userSettings.set(wineLogEnabled, forKey: "wineLogEnabled") } }
    var gameLaunchArguments: String { didSet { userSettings.set(gameLaunchArguments, forKey: "gameLaunchArguments") } }; var isStartingWineTool = false
    var wishes: [WishRecord] = []
    var wishResultCatalog = WishResultCatalog(records: [])
    var wishOverviewSummary = WishOverviewSummary(records: [])
    var wishPityEntries: [WishPityEntry] = []
    var gachaHistory: [HistoryWishEvent] = []
    var wishStatistics: [WishStatistics] = []
    var bannerDetails: [WishBannerDetail] = []
    var characters: [GameCharacter] = []; var selectedCharacterId: String?; var characterSearchText = ""
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
    @ObservationIgnored var companionSelectionIntent = 0
    @ObservationIgnored var companionDataGeneration = 0
    @ObservationIgnored var wishPresentationIntent = 0
    @ObservationIgnored var gachaHistoryPresentationIntent = 0
    @ObservationIgnored let achievementSelectionGate = AsyncSerialGate()
    var message: String?; var resourceSetupError: String?
    var statusMessage: String?; var statusMessageRevision = 0
    var isWishOperationActive = false
    var wishOperation: WishOperationState? {
        didSet {
            let active = wishOperation != nil
            if isWishOperationActive != active { isWishOperationActive = active }
        }
    }
    var triggerWishImport = false
    var triggerWishExport = false
    var triggerWishClear = false; var manualWishUID: String?
    var showsLoginBeforeLaunch = false
    var speedLimitKB = 0
    let loginDeferralKey = "loginLaunchDeferrals"
    var qrLoginAttempt = 0
    var loginGeneration = 0
    var selectedRole: GameRole? {
        roles.first(where: \.selected) ?? roles.first
    }

    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }
        gameRuntimeReady = runtimeInstaller.isGameInstalled()
        runtimeErrorMessage = nil
        await coreHost.start()
        guard coreHost.client != nil else {
            if case .failed(_, let coreMessage) = coreHost.state { message = coreMessage }
            return
        }
        await prepareInitialResources(); if needsMetadataSetup { return }
        await refreshAccount()
        await loadNotificationSettings()
        await refreshGame()
        await refreshSpeedLimit()
        let savedKB = userSettings.integer(forKey: "downloadSpeedLimitKB")
        if savedKB > 0 { await setSpeedLimit(savedKB) }
        if selectedRole != nil { await loadCompanionData(); await loadValueData() }
        Task { await checkForAppUpdate(silent: true) }
    }
    func retryBootstrap() async {
        await coreHost.stop()
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
        } catch let error as LauncherCoreError {
            message = Self.presentableMessage(error)
        } catch {
            message = Self.presentableMessage(error)
        }
    }

    func requireClient() throws -> LauncherClient {
        guard let client = coreHost.client else {
            throw LauncherError.coreUnavailable
        }
        return client
    }

}
