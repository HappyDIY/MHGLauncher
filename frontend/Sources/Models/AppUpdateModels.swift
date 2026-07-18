import Foundation
import Observation

struct AppUpdateManifest: Codable, Sendable, Equatable {
    let version: String
    let downloadUrl: URL
    let sha256: String
    let size: Int64
    let changelog: String

    func isNewer(than currentVersion: String) -> Bool {
        guard let remote = AppVersion(version), let current = AppVersion(currentVersion) else { return false }
        return remote > current
    }
}

@MainActor
@Observable
final class AppUpdateState {
    var manifest: AppUpdateManifest?
    var isChecking = false
    var isDownloading = false
    var errorMessage: String?
    var showsSheet = false
}

struct AppVersion: Comparable, Sendable {
    private let core: [Int]
    private let prerelease: [String]?

    init?(_ value: String) {
        let parts = value.split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = parts[0].split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        core = numbers
        prerelease = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.core != rhs.core {
            for (left, right) in zip(lhs.core, rhs.core) where left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(left), .some(right)):
            for index in 0..<min(left.count, right.count) where left[index] != right[index] {
                let leftNumber = Int(left[index]), rightNumber = Int(right[index])
                if let leftNumber, let rightNumber { return leftNumber < rightNumber }
                if leftNumber != nil { return true }
                if rightNumber != nil { return false }
                return left[index] < right[index]
            }
            return left.count < right.count
        }
    }
}
