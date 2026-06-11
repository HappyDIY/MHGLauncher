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

struct WishOperationLog: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let emphasized: Bool
}

struct WishOperationState: Identifiable, Sendable {
    let id = UUID()
    let kind: WishOperationKind
    var status: WishOperationStatus = .running
    var progress = 0.02
    var logs: [WishOperationLog] = []

    var statusText: String {
        switch status {
        case .running: "处理中"
        case .succeeded: "已完成"
        case .failed: "执行失败"
        }
    }

    mutating func update(
        progress: Double,
        message: String,
        emphasized: Bool = false
    ) {
        self.progress = min(max(progress, self.progress), 1)
        logs.append(WishOperationLog(message: message, emphasized: emphasized))
    }

    mutating func succeed(_ message: String) {
        status = .succeeded
        update(progress: 1, message: message, emphasized: true)
    }

    mutating func fail(_ message: String) {
        status = .failed
        update(progress: progress, message: message, emphasized: true)
    }
}
