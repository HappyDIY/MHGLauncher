import Foundation
import Testing
@testable import MHGLauncher

@Suite("最终免责声明")
struct FinalDisclaimerConsentTests {
    @Test("未同意时展示并在同意后记住")
    func persistence() {
        let suite = "FinalDisclaimerConsentTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(FinalDisclaimerConsent.shouldPresent(defaults: defaults, environment: [:]))
        FinalDisclaimerConsent.accept(defaults: defaults)
        #expect(!FinalDisclaimerConsent.shouldPresent(defaults: defaults, environment: [:]))
    }

    @Test("确认内容必须一字不差")
    func exactConfirmation() {
        #expect(FinalDisclaimerConsent.matches(FinalDisclaimerConsent.confirmationText))
        #expect(!FinalDisclaimerConsent.matches("\(FinalDisclaimerConsent.confirmationText) "))
        #expect(!FinalDisclaimerConsent.matches("因使用本工具导致的损失由用户承担"))
    }
}
