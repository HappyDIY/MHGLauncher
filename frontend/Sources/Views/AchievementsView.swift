import AppKit
import SwiftUI
struct AchievementsView: View {
    @Bindable var store: LauncherStore
    @State var searchText = ""
    @State var selectedGoal: Int?
    @State var uncompletedFirst = true
    @State var dailyOnly = false

    var body: some View {
        let presentation = achievementPresentation
        VStack(alignment: .leading, spacing: 16) {
            header(presentation).motionEntrance(order: 0)
            if store.selectedRole == nil {
                ContentUnavailableView(
                    "需要选择角色", systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("登录并选择角色后可管理成就档案。")
                )
            } else if let error = store.value.achievementError {
                ContentUnavailableView {
                    Label("无法载入成就", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("重试") { Task { await store.loadValueData() } }
                }
                .accessibilityLiveRegion(.assertive)
            } else if !store.value.achievementLoaded {
                ProgressView("正在载入成就")
                    .accessibilityLiveRegion(.polite)
            } else if store.selectedAchievementArchive == nil {
                emptyArchive.motionTransition(.content)
            } else {
                toolbar(presentation).motionEntrance(order: 1)
                content(presentation).motionEntrance(order: 2)
            }
        }
        .task(id: store.selectedRole?.uid) {
            await store.loadValueData()
            restoreGoalSelection()
        }
        .motionAnimation(.content, value: achievementAnimationID)
    }

    private func header(_ presentation: AchievementPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: "成就管理", subtitle: headerSubtitle(presentation))
            HStack(spacing: 10) {
                Menu("UIAF", systemImage: "doc.badge.gearshape") {
                    Button("导入 UIAF", systemImage: "square.and.arrow.down") { importFile() }
                    Button("导出 UIAF", systemImage: "square.and.arrow.up") { exportFile() }
                        .disabled(store.value.achievementEntries.isEmpty)
                }
                .disabled(store.selectedAchievementArchive == nil)
                Menu("云同步", systemImage: "icloud") {
                    Button("上传成就", systemImage: "square.and.arrow.up") {
                        Task { await store.uploadCloudAchievements() }
                    }
                    Button("取回成就", systemImage: "square.and.arrow.down") {
                        Task { await store.retrieveCloudAchievements() }
                    }
                }
                .disabled(!canCloudSync)
            }
        }
    }

    private func toolbar(_ presentation: AchievementPresentation) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                TextField("搜索标题、描述、版本或成就 ID", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                Text("UID \(store.selectedAchievementArchive?.name ?? "-")")
                    .foregroundStyle(.secondary)
            }
            GridRow {
                Toggle("未完成优先", isOn: $uncompletedFirst).toggleStyle(.checkbox)
                Toggle("每日委托", isOn: $dailyOnly).toggleStyle(.checkbox)
                Text("\(presentation.entries.count) / \(store.value.achievementEntries.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    private func content(_ presentation: AchievementPresentation) -> some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 14) {
                goalList(presentation).frame(width: min(330, geometry.size.width * 0.34))
                achievementList(presentation)
            }
        }
    }

    private func goalList(_ presentation: AchievementPresentation) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                goalButtons(presentation)
            }
            .padding(8)
        }
        .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 12)) }
    }

    private func goalButtons(_ presentation: AchievementPresentation) -> some View {
        ForEach(presentation.goals) { goal in
            Button {
                selectGoal(goal.id)
            } label: {
                let stats = presentation.stats[goal.id] ?? (0, 0)
                AchievementGoalCell(
                    goal: goal,
                    finished: stats.0,
                    total: stats.1,
                    selected: selectedGoal == goal.id
                )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedGoal == goal.id ? .isSelected : [])
            .accessibilityValue(selectedGoal == goal.id ? "已选择" : "未选择")
        }
    }

    private func achievementList(_ presentation: AchievementPresentation) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(presentation.entries) { entry in
                    AchievementEntryRow(
                        entry: entry,
                        checked: isChecked(entry)
                    ) { checked in
                        Task { await store.saveAchievement(entry, checked: checked) }
                    }
                    .motionScrollAppearance()
                }
            }
            .padding(8)
        }
        .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 12)) }
    }

    private var emptyArchive: some View {
        ContentUnavailableView {
            Label("还没有成就档案", systemImage: "trophy")
        } description: {
            Text("选择角色后会自动创建以 UID 命名的成就档案。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var canCloudSync: Bool {
        guard let uid = store.selectedRole?.uid else { return false }
        return store.value.cloudSession?.uid == uid && !store.isBusy
    }

    func selectGoal(_ id: Int) {
        selectedGoal = id
        guard let uid = store.selectedRole?.uid else { return }
        AchievementGoalSelection.save(id, uid: uid)
    }

    func restoreGoalSelection() {
        guard let uid = store.selectedRole?.uid else { selectedGoal = nil; return }
        selectedGoal = AchievementGoalSelection.restore(uid: uid, goals: store.value.achievementGoals)
    }

}
