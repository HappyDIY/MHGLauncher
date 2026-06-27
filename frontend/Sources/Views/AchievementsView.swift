import SwiftUI

struct AchievementsView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "成就管理", subtitle: archiveTitle)
            HStack {
                Button {
                    Task { await store.createAchievementArchive() }
                } label: {
                    Label("新建档案", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Text("\(store.value.achievements.count) 条记录")
                    .foregroundStyle(.secondary)
            }
            GlassCard("录入", icon: "checklist") {
                HStack {
                    TextField("成就 ID", text: $store.value.achievementDraftId)
                        .textFieldStyle(.roundedBorder)
                    Stepper("进度 \(store.value.achievementDraftCurrent)", value: $store.value.achievementDraftCurrent, in: 0...999)
                    Button {
                        Task { await store.saveAchievementDraft() }
                    } label: {
                        Label("保存", systemImage: "checkmark")
                    }
                }
            }
            List(store.value.achievements) { item in
                HStack {
                    Text("#\(item.achievementId)")
                    Spacer()
                    Text("进度 \(item.current)")
                    Text("状态 \(item.status)")
                        .foregroundStyle(.secondary)
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
        }
        .task { await store.loadValueData() }
        .motionEntrance(.content)
    }

    private var archiveTitle: String {
        store.value.achievementArchives.first(where: \.selected)?.name ?? "未选择档案"
    }
}
