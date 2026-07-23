import Foundation
import Testing
@testable import MHGLauncher

@Suite("应用启动保护")
struct SingleInstanceGuardTests {
    @Test("同一锁文件只允许一个实例持有")
    func exclusiveLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "mhg-instance-\(UUID().uuidString)")
        let lockURL = directory.appending(path: "app.lock")
        defer { try? FileManager.default.removeItem(at: directory) }

        var first = SingleInstanceGuard.acquire(lockURL: lockURL)
        #expect(first != nil)
        #expect(SingleInstanceGuard.acquire(lockURL: lockURL) == nil)
        first = nil
        #expect(SingleInstanceGuard.acquire(lockURL: lockURL) != nil)
    }

    @Test("启动锁拒绝符号链接且不改写目标")
    func rejectsSymlinkLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "mhg-instance-link-\(UUID().uuidString)")
        let target = directory.appending(path: "target")
        let lockURL = directory.appending(path: "app.lock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("保留".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(SingleInstanceGuard.acquire(lockURL: lockURL) == nil)
        #expect(try Data(contentsOf: target) == Data("保留".utf8))
    }

    @Test("启动锁路径支持环境变量覆盖")
    func lockPathOverride() {
        let url = SingleInstanceGuard.defaultLockURL(
            environment: ["MHG_INSTANCE_LOCK_PATH": "/tmp/mhg-test.lock"]
        )
        #expect(url.path == "/tmp/mhg-test.lock")
    }

    @Test("钥匙串提示仅在交互启动显示一次")
    func keychainPromptPolicy() throws {
        let suiteName = "mhg-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(KeychainAccessPrompt.shouldPresent(defaults: defaults, environment: [:]))
        defaults.set(true, forKey: KeychainAccessPrompt.defaultsKey)
        #expect(!KeychainAccessPrompt.shouldPresent(defaults: defaults, environment: [:]))
        defaults.set(false, forKey: KeychainAccessPrompt.defaultsKey)
        #expect(!KeychainAccessPrompt.shouldPresent(
            defaults: defaults,
            environment: ["MHG_SMOKE_MODE": "1"]
        ))
    }

    @Test("钥匙串引导授权成功后记录状态")
    func keychainGuideAuthorizationRecordsState() throws {
        let suiteName = "mhg-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let keychain = KeychainStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? keychain.delete(account: "system:keychain-access-probe")
        }

        switch KeychainAccessPrompt.authorizeAfterGuide(
            defaults: defaults,
            keychain: keychain
        ) {
        case .success:
            #expect(!KeychainAccessPrompt.shouldPresent(defaults: defaults, environment: [:]))
        case .failure(let error):
            throw error
        }
    }
}
