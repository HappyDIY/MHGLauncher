import SwiftUI

struct GachaHistoryView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "历史卡池", subtitle: "按版本和卡池类型查看活动祈愿，并关联本地抽卡统计。")
                HStack {
                    Button {
                        Task { await store.refreshGachaEvents() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Text("\(store.value.gachaEvents.count) 个卡池")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(store.value.gachaEvents) { event in
                        GlassCard(event.name, icon: icon(for: event.gachaType)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("版本 \(event.version.nonempty ?? "未知")")
                                    .font(.subheadline.weight(.semibold))
                                Text(event.startedAt.formatted(date: .abbreviated, time: .shortened))
                                Text(event.endedAt.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                                Text(upText(event.orangeUp))
                                    .lineLimit(2)
                                Text(upText(event.purpleUp))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .motionEntrance(.content)
        }
        .task { await store.loadValueData() }
    }

    private func icon(for type: String) -> String {
        type == "302" ? "shield.lefthalf.filled" : "sparkles"
    }

    private func upText(_ values: [String]) -> String {
        values.isEmpty ? "UP 信息待同步" : values.joined(separator: "、")
    }
}
