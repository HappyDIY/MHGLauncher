import SwiftUI

struct NotesView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    PageHeader(
                        title: "实时便笺",
                        subtitle: refreshedText
                    )
                    Spacer()
                    Button("刷新") {
                        Task { await store.refreshNote() }
                    }
                    .buttonStyle(.glassProminent)
                    .motionHover(.prominent)
                }
                .motionEntrance(order: 0)
                if let note = store.dailyNote {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 16
                    ) {
                        noteCard(
                            "原粹树脂",
                            icon: "drop.fill",
                            value: "\(note.currentResin)/\(note.maxResin)"
                        )
                        .motionScrollAppearance()
                        .motionEntrance(order: 1)
                        noteCard(
                            "每日委托",
                            icon: "checkmark.circle",
                            value: "\(note.finishedTasks)/\(note.totalTasks)"
                        )
                        .motionScrollAppearance()
                        .motionEntrance(order: 2)
                        noteCard(
                            "探索派遣",
                            icon: "figure.walk",
                            value: "\(note.expeditionsFinished)/\(note.expeditionsTotal)"
                        )
                        .motionScrollAppearance()
                        .motionEntrance(order: 3)
                        noteCard(
                            "洞天宝钱",
                            icon: "house",
                            value: "\(note.currentHomeCoin)/\(note.maxHomeCoin)"
                        )
                        .motionScrollAppearance()
                        .motionEntrance(order: 4)
                        noteCard(
                            "周本折扣",
                            icon: "calendar",
                            value: "\(note.weeklyBossRemaining)"
                        )
                        .motionScrollAppearance()
                        .motionEntrance(order: 5)
                        noteCard(
                            "参量质变仪",
                            icon: "arrow.triangle.2.circlepath",
                            value: note.transformerReady ? "可使用" : "冷却中"
                        )
                        .motionScrollAppearance()
                        .motionEntrance(order: 6)
                    }
                    .motionTransition(.content)
                } else {
                    ContentUnavailableView(
                        "暂无便笺数据",
                        systemImage: "note.text",
                        description: Text("登录后点击刷新获取实时便笺")
                    )
                    .motionTransition(.content)
                }
            }
        }
        .motionAnimation(.content, value: store.dailyNote != nil)
    }

    private var refreshedText: String {
        guard let date = store.dailyNote?.refreshedAt else { return "尚未刷新" }
        return "更新于 \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func noteCard(
        _ title: String,
        icon: String,
        value: String
    ) -> some View {
        GlassCard(title, icon: icon) {
            Text(value)
                .font(.largeTitle.bold())
                .contentTransition(.numericText())
                .motionAnimation(.content, value: value)
        }
    }
}
