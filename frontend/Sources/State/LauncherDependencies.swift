import Foundation

protocol LauncherClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemLauncherClock: LauncherClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
struct LauncherDependencies {
    let backend: BackendProcess
    let runtimeInstaller: RuntimeInstaller
    let keychain: any KeychainStoring
    let userSettings: UserDefaults
    let notifications: any UserNotificationDelivering
    let clock: any LauncherClock

    init(
        backend: BackendProcess = BackendProcess(),
        runtimeInstaller: RuntimeInstaller = RuntimeInstaller(),
        keychain: any KeychainStoring = KeychainStore(),
        userSettings: UserDefaults = .standard,
        notifications: any UserNotificationDelivering = UserNotificationService(),
        clock: any LauncherClock = SystemLauncherClock()
    ) {
        self.backend = backend
        self.runtimeInstaller = runtimeInstaller
        self.keychain = keychain
        self.userSettings = userSettings
        self.notifications = notifications
        self.clock = clock
    }
}
