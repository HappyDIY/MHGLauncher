import Foundation

enum FinalDisclaimerConsent {
    static let confirmationText = "因使用本工具导致的封号及其他损失均由用户自行承担与开发者无关"
    static let defaultsKey = "finalDisclaimerAcceptedV1"

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

    static func matches(_ input: String) -> Bool {
        input == confirmationText
    }

    static func accept(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }
}
