import AppKit
import Foundation

enum KeychainAccessPrompt {
    static let defaultsKey = "keychainAccessPromptAccepted"

    static func shouldPresent(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard environment["MHG_SMOKE_MODE"] != "1",
              environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        return !defaults.bool(forKey: defaultsKey)
    }

    @MainActor
    static func presentIfNeeded(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) {
        guard shouldPresent(defaults: defaults) else { return }
        let alert = NSAlert()
        alert.messageText = "需要授权访问钥匙串"
        alert.informativeText = "启动器会把米游社登录凭据保存在 macOS 钥匙串中。系统弹窗出现时，请允许访问以便登录、启动游戏和同步记录正常工作。"
        alert.addButton(withTitle: "继续")
        alert.runModal()
        defaults.set(true, forKey: defaultsKey)
        try? keychain.prepareAccess()
    }
}
