import SwiftUI

struct GachaHistoryView: View {
    @Bindable var store: LauncherStore
    @State private var selectedID: String?

    private var selection: HistoryWishEvent? {
        store.gachaHistory.first { $0.id == selectedID } ?? store.gachaHistory.first
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
        .onChange(of: store.gachaHistory.map(\.id)) {
            if !(selectedID.map { id in store.gachaHistory.contains { $0.id == id } } ?? false) {
                selectedID = store.gachaHistory.first?.id
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
        let count = store.gachaHistory.reduce(0) { $0 + $1.total }
        return "\(role.nickname) · UID \(role.uid) · 已匹配 \(store.gachaHistory.count) 个卡池、\(count) 抽"
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
        .background {
            Color.clear.glassEffect(
                .regular.tint(.blue.opacity(0.06)),
                in: .rect(cornerRadius: 22)
            )
        }
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let sidebarWidth = min(max(geometry.size.width * 0.34, 280), 340)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    listPane.frame(width: sidebarWidth)
                    detailPane.frame(minWidth: 420, maxWidth: .infinity)
                }
            }
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("活动卡池", systemImage: "rectangle.stack.fill")
                    .font(.headline)
                Spacer()
                Text("\(store.gachaHistory.count) 个")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider().padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.gachaHistory) { wish in
                        HistoryWishRow(
                            wish: wish,
                            selected: selection?.id == wish.id
                        ) { selectedID = wish.id }
                    }
                }
                .padding(10)
            }
        }
        .background {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selection {
            HistoryWishDetail(wish: selection)
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
