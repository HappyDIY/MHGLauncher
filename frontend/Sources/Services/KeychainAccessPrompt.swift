import Foundation

enum KeychainAccessPrompt {
    static let defaultsKey = "keychainAccessPromptAcceptedV3"

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

    static func authorizeAfterGuide(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) -> Result<Void, Error> {
        do {
            try keychain.prepareAccess()
            defaults.set(true, forKey: defaultsKey)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
