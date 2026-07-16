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
                GeometryReader { geometry in
                    if geometry.size.width >= 900 {
                        HStack(spacing: 0) {
                            listPane.frame(width: min(439, geometry.size.width * 0.42))
                            Divider()
                            detailPane.frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 12) {
                            listPane.frame(height: min(280, geometry.size.height * 0.42))
                            detailPane
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .motionEntrance(order: 1)
            }
        }
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
        HStack(alignment: .center, spacing: 12) {
            PageHeader(title: "历史祈愿", subtitle: subtitle)
            Button("刷新卡池", systemImage: "arrow.clockwise") {
                Task { await store.refreshGachaEvents() }
            }
            .buttonStyle(.glassProminent)
            .motionHover(.prominent)
            Button("同步记录", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                Task { await store.syncWishes() }
            }
            .buttonStyle(.glass)
            .motionHover()
            .disabled(store.isWishOperationActive)
        }
    }

    private var subtitle: String {
        guard let role = store.selectedRole else { return "请先登录账号并同步祈愿记录" }
        let count = store.gachaHistory.reduce(0) { $0 + $1.total }
        return "\(role.nickname) · UID \(role.uid) · 已匹配 \(store.gachaHistory.count) 个卡池、\(count) 抽"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有可展示的历史祈愿", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("刷新历史卡池并同步祈愿记录后，这里会按活动卡池还原 UP、横幅和抽取结果。")
        } actions: {
            Button("刷新卡池") { Task { await store.refreshGachaEvents() } }
                .buttonStyle(.glassProminent)
                .motionHover(.prominent)
            Button("同步记录") { Task { await store.syncWishes() } }
                .buttonStyle(.glass)
                .motionHover()
                .disabled(store.isWishOperationActive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var listPane: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.gachaHistory) { wish in
                    HistoryWishRow(
                        wish: wish,
                        selected: selection?.id == wish.id
                    ) {
                        selectedID = wish.id
                    }
                }
            }
            .padding(12)
        }
        .background(.thinMaterial.opacity(0.28))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selection {
            HistoryWishDetail(wish: selection)
        }
    }
}
