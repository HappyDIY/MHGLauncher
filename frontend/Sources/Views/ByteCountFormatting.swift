import Foundation

// 复用单个 ByteCountFormatter 实例，避免下载进度每 0.2s tick 及滚动重绘时
// 反复分配格式化器。所有调用点均在主线程（@MainActor 视图）访问。
@MainActor
enum ByteCountFormatting {
    private static let formatter: ByteCountFormatter = {
        let value = ByteCountFormatter()
        value.countStyle = .file
        return value
    }()

    static func fileSize(_ byteCount: Int64) -> String {
        formatter.string(fromByteCount: byteCount)
    }
}
