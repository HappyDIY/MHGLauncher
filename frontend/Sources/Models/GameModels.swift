import Foundation

enum GameStatus: String, Codable, Sendable {
    case notInstalled = "not_installed"
    case ready
    case updateAvailable = "update_available"
    case busy
    case damaged
}

struct GameState: Codable, Sendable {
    let installPath: String
    let installedVersion: String
    let availableVersion: String
    let status: GameStatus
    let updateKind: String?
    let downloadBytes: Int64?
}

enum JobKind: String, Codable {
    case install
    case update
    case verify
}

enum JobStatus: String, Codable, Sendable {
    case queued
    case running
    case paused
    case completed
    case cancelled
    case failed
}

struct ChunkProgress: Codable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let bytesDone: Int64
    let total: Int64

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(bytesDone) / Double(total)
    }
}

struct GameJob: Codable, Sendable, Identifiable {
    let id: String
    let kind: JobKind
    let status: JobStatus
    let completedBytes: Int64
    let totalBytes: Int64
    let message: String
    let downloadSpeed: Int64
    let chunksCompleted: Int64
    let chunksTotal: Int64
    let activeChunks: [ChunkProgress]

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(completedBytes) / Double(totalBytes)
    }
}

struct StartJobRequest: Codable {
    let kind: JobKind
    let installPath: String
}

struct ControlJobRequest: Codable {
    let action: String
}
