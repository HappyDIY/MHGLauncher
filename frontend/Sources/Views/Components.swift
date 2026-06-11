import SwiftUI

struct GlassCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

struct MetricView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension GameStatus {
    var title: String {
        switch self {
        case .notInstalled: "未安装"
        case .ready: "可以使用"
        case .updateAvailable: "有可用更新"
        case .busy: "处理中"
        case .damaged: "需要修复"
        }
    }
}

extension JobStatus {
    var title: String {
        switch self {
        case .queued: "等待中"
        case .running: "处理中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .cancelled: "已取消"
        case .failed: "失败"
        }
    }
}

extension String {
    var nonempty: String? { isEmpty ? nil : self }
}
