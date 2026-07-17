import SwiftUI

struct GachaHistoryView: View {
    @Bindable var store: LauncherStore
    @State private var selectedID: String?
    @State private var category = HistoryWishCategory.character

    private var visibleWishes: [HistoryWishEvent] {
        category.wishes(in: store.gachaHistory)
    }

    private var selection: HistoryWishEvent? {
        visibleWishes.first { $0.id == selectedID } ?? visibleWishes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header.motionEntrance(order: 0)
            if store.gachaHistory.isEmpty {
                emptyState.motionTransition(.content)
            } else {
                workspace.motionEntrance(order: 1)
            }
        }
        .toolbar { toolbarActions }
        .task {
            await store.loadValueData()
            if store.wishes.isEmpty { await store.loadCompanionData() }
        }
        .onChange(of: visibleWishes.map(\.id)) {
            if !(selectedID.map { id in visibleWishes.contains { $0.id == id } } ?? false) {
                selectedID = visibleWishes.first?.id
            }
        }
    }

    private var header: some View {
        PageHeader(title: "历史祈愿", subtitle: subtitle)
    }

    @ToolbarContentBuilder
    private var toolbarActions: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("刷新卡池", systemImage: "arrow.clockwise") {
                Task { await store.refreshGachaEvents() }
            }
            .buttonStyle(.glass)
            .motionHover()
            .disabled(store.isBusy || store.selectedRole == nil)
            Button("同步记录", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                Task { await store.syncWishes() }
            }
            .buttonStyle(.glassProminent)
            .motionHover(.prominent)
            .disabled(store.isWishOperationActive || store.selectedRole == nil)
        }
    }

    private var subtitle: String {
        guard let role = store.selectedRole else { return "请先登录账号并同步祈愿记录" }
        let count = visibleWishes.reduce(0) { $0 + $1.total }
        return "\(role.nickname) · UID \(role.uid) · \(category.rawValue)祈愿 \(visibleWishes.count) 个时段、\(count) 抽"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "sparkles.rectangle.stack")
        } description: {
            Text(emptyDescription)
        } actions: {
            Button("同步记录") { Task { await store.syncWishes() } }
                .buttonStyle(.glassProminent)
                .motionHover(.prominent)
                .disabled(store.isWishOperationActive || store.selectedRole == nil)
            Button("刷新卡池") { Task { await store.refreshGachaEvents() } }
                .buttonStyle(.glass)
                .motionHover()
                .disabled(store.isBusy || store.selectedRole == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(
            .regular.tint(.blue.opacity(0.06)),
            in: .rect(cornerRadius: 22)
        )
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let sidebarWidth = min(max(geometry.size.width * 0.34, 280), 340)
            HStack(spacing: 12) {
                listPane.frame(width: sidebarWidth)
                detailPane.frame(minWidth: 420, maxWidth: .infinity)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            Picker("祈愿分类", selection: $category) {
                ForEach(HistoryWishCategory.allCases) { value in
                    Label(value.rawValue, systemImage: value.icon)
                        .tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider().padding(.horizontal, 12)
            HStack(spacing: 8) {
                Label("祈愿时段", systemImage: "rectangle.stack.fill")
                    .font(.headline)
                Spacer()
                Text("\(visibleWishes.count) 个")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider().padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleWishes) { wish in
                        HistoryWishRow(
                            wish: wish,
                            selected: selection?.id == wish.id
                        ) { selectedID = wish.id }
                    }
                }
                .padding(10)
            }
        }
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selection {
            HistoryWishDetail(wish: selection, category: category)
        } else {
            ContentUnavailableView(
                "暂无\(category.rawValue)祈愿记录",
                systemImage: category.icon,
                description: Text("同步记录或切换分类后重试。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }

    private var emptyTitle: String {
        store.wishes.isEmpty ? "还没有祈愿记录" : "没有匹配的历史卡池"
    }

    private var emptyDescription: String {
        store.wishes.isEmpty
            ? "同步祈愿记录后，这里会自动还原活动卡池、UP 与抽取结果。"
            : "刷新卡池元数据后重试，未落在活动时段内的记录仍可在祈愿记录页查看。"
    }
}
