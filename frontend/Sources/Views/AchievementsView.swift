import AppKit
import SwiftUI

struct AchievementsView: View {
    @Bindable var store: LauncherStore
    @State var searchText = ""
    @State var selectedGoal: Int?
    @State var layoutMode: AchievementLayoutMode = .list
    @State var uncompletedFirst = true
    @State var dailyOnly = false
    @State var confirmsRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header.motionEntrance(order: 0)
            if store.selectedAchievementArchive == nil {
                emptyArchive.motionTransition(.content)
            } else {
                toolbar.motionEntrance(order: 1)
                content.motionEntrance(order: 2)
            }
        }
        .confirmationDialog("删除当前成就档案？", isPresented: $confirmsRemoval) {
            Button("删除", role: .destructive) {
                Task { await store.removeSelectedAchievementArchive() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("档案内的成就记录会一并删除，此操作无法撤销。")
        }
        .task { await store.loadValueData() }
        .motionAnimation(.content, value: store.value.achievementEntries)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PageHeader(title: "成就管理", subtitle: headerSubtitle)
            Button("新建档案", systemImage: "plus") {
                Task { await store.createAchievementArchive() }
            }
            .buttonStyle(.glassProminent)
            .motionHover(.prominent)
            Button("删除档案", systemImage: "trash", role: .destructive) {
                confirmsRemoval = true
            }
            .buttonStyle(.glass)
            .motionHover(.destructive)
            .disabled(store.selectedAchievementArchive == nil)
            Menu {
                Button("导入 UIAF", systemImage: "square.and.arrow.down") { importFile() }
                Button("导出 UIAF", systemImage: "square.and.arrow.up") { exportFile() }
                    .disabled(store.value.achievementEntries.isEmpty)
            } label: {
                Label("UIAF", systemImage: "doc.badge.gearshape")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .motionHover()
            .disabled(store.selectedAchievementArchive == nil)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("布局", selection: $layoutMode) {
                ForEach(AchievementLayoutMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 128)
            TextField("搜索标题、描述、版本或成就 ID", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260)
            Picker("档案", selection: archiveSelection) {
                ForEach(store.value.achievementArchives) { archive in
                    Text(archive.name).tag(archive.id)
                }
            }
            .frame(width: 190)
            Toggle("未完成优先", isOn: $uncompletedFirst)
                .toggleStyle(.checkbox)
            Toggle("每日委托", isOn: $dailyOnly)
                .toggleStyle(.checkbox)
            Spacer()
            Text("\(filteredEntries.count) / \(store.value.achievementEntries.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var content: some View {
        GeometryReader { geometry in
            if layoutMode == .list {
                HStack(alignment: .top, spacing: 14) {
                    goalList.frame(width: min(330, geometry.size.width * 0.34))
                    achievementList
                }
            } else {
                VStack(spacing: 14) {
                    goalGrid.frame(height: min(260, max(180, geometry.size.height * 0.34)))
                    achievementList
                }
            }
        }
    }

    private var goalList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                goalButtons
            }
            .padding(8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var goalGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                goalButtons
            }
            .padding(8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var goalButtons: some View {
        ForEach(visibleGoals) { goal in
            Button {
                selectedGoal = selectedGoal == goal.id ? nil : goal.id
            } label: {
                let stats = goalStats[goal.id] ?? (0, 0)
                AchievementGoalCell(
                    goal: goal,
                    finished: stats.0,
                    total: stats.1,
                    selected: selectedGoal == goal.id
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var achievementList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredEntries) { entry in
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
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var emptyArchive: some View {
        ContentUnavailableView {
            Label("还没有成就档案", systemImage: "trophy")
        } description: {
            Text("新建档案后即可导入 UIAF，或手动勾选成就同步完成进度。")
        } actions: {
            Button("新建档案") { Task { await store.createAchievementArchive() } }
                .buttonStyle(.glassProminent)
                .motionHover(.prominent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var archiveSelection: Binding<String> {
        Binding {
            store.selectedAchievementArchive?.id ?? ""
        } set: { id in
            guard let archive = store.value.achievementArchives.first(where: { $0.id == id }) else { return }
            Task { await store.selectAchievementArchive(archive) }
        }
    }

    private var headerSubtitle: String {
        "\(store.selectedAchievementArchive?.name ?? "未选择档案") · \(finishDescription)"
    }
}
