import Foundation
@testable import MHGLauncher

final class MemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func prepareAccess() throws {}

    func save(_ value: String, account: String) throws {
        lock.withLock { values[account] = value }
    }

    func read(account: String) throws -> String? {
        lock.withLock { values[account] }
    }

    func delete(account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: account) }
    }
}
