import Foundation

enum WishOperationKind: String, Sendable {
    case sync
    case importUIGF
    case exportUIGF
    case clearAll

    var title: String {
        switch self {
        case .sync: "同步祈愿记录"
        case .importUIGF: "导入 UIGF 数据"
        case .exportUIGF: "导出 UIGF 数据"
        case .clearAll: "清空全部祈愿记录"
        }
    }

    var icon: String {
        switch self {
        case .sync: "arrow.trianglehead.2.clockwise.rotate.90"
        case .importUIGF: "square.and.arrow.down"
        case .exportUIGF: "square.and.arrow.up"
        case .clearAll: "trash"
        }
    }
}

enum WishOperationStatus: Sendable {
    case running
    case succeeded
    case failed
}

enum WishTaskStatus: String, Codable, Sendable {
    case queued
    case running
    case completed
    case failed
}

struct WishTaskLogPayload: Codable, Sendable {
    let sequence: Int
    let message: String
    let emphasized: Bool
}

struct WishTaskSnapshot: Codable, Sendable {
    let id: String
    let kind: String
    let status: WishTaskStatus
    let progress: Double?
    let logs: [WishTaskLogPayload]
    let result: [String: Int]?
    let error: String
    let errorCode: String?

    var failureMessage: String {
        switch errorCode {
        case "wish_sync_limited": "访问过于频繁，请稍后再同步祈愿记录"
        default: error
        }
    }
}

struct WishOperationLog: Identifiable, Sendable {
    let id: String
    let message: String
    let emphasized: Bool

    init(
        id: String = UUID().uuidString,
        message: String,
        emphasized: Bool
    ) {
        self.id = id
        self.message = message
        self.emphasized = emphasized
    }
}

struct WishOperationState: Identifiable, Sendable {
    let id = UUID()
    let kind: WishOperationKind
    var status: WishOperationStatus = .running
    var progress: Double?
    var logs: [WishOperationLog] = []
    private var lastBackendSequence = 0

    init(kind: WishOperationKind) {
        self.kind = kind
    }

    var statusText: String {
        switch status {
        case .running: "处理中"
        case .succeeded: "已完成"
        case .failed: "执行失败"
        }
    }

    mutating func update(
        progress: Double?,
        message: String,
        emphasized: Bool = false
    ) {
        self.progress = progress.map { min(max($0, 0), 1) }
        logs.append(WishOperationLog(message: message, emphasized: emphasized))
        trimLogs()
    }

    mutating func apply(_ task: WishTaskSnapshot) {
        for entry in task.logs where entry.sequence > lastBackendSequence {
            logs.append(
                WishOperationLog(
                    id: "\(task.id)-\(entry.sequence)",
                    message: entry.message,
                    emphasized: entry.emphasized
                )
            )
        }
        lastBackendSequence = max(lastBackendSequence, task.logs.last?.sequence ?? 0)
        progress = task.progress.map { min(max($0, 0), 1) }
        status = task.status == .failed ? .failed : .running
        trimLogs()
    }

    private mutating func trimLogs() {
        if logs.count > 24 {
            logs.removeFirst(logs.count - 24)
        }
    }

    mutating func succeed(_ message: String) {
        status = .succeeded
        update(progress: 1, message: message, emphasized: true)
    }

    mutating func fail(_ message: String) {
        status = .failed
        if logs.last?.message != message {
            update(progress: progress, message: message, emphasized: true)
        }
    }
}
