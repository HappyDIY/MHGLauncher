import AppKit
import SwiftUI

struct WishesView: View {
    static let uigfUpgraderURL = URL(string: "https://upgrader.uigf.org/")!

    @Bindable var store: LauncherStore
    @State private var confirmsClear = false
    @State private var showsHistory = false
    @State private var selectedBanner: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
                .motionEntrance(order: 0)
            if !store.companionLoaded {
                loadingPlaceholder
                    .motionTransition(.content)
            } else if store.wishes.isEmpty {
                emptyState
                    .motionTransition(.content)
            } else {
                WishOverviewHero(
                    records: store.wishes,
                    details: store.bannerDetails,
                    uid: store.selectedRole?.uid
                )
                .motionEntrance(order: 1)
                workspace.motionEntrance(order: 2)
            }
        }
        .overlay {
            if let operation = store.wishOperation {
                WishOperationOverlay(operation: operation) {
                    store.wishOperation = nil
                }
            }
        }
        .motionAnimation(.emphasis, value: store.wishOperation?.id)
        .motionAnimation(.content, value: store.companionLoaded)
        .confirmationDialog(
            "永久清空全部祈愿记录？",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("认证并清空", role: .destructive) {
                Task { await store.clearAllWishes() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销，继续后需要使用 Touch ID 或 Mac 登录密码确认。")
        }
        .sheet(isPresented: $showsHistory) {
            WishHistoryPanel(
                records: store.wishes,
                selectedGachaType: selectedDetail?.gachaType
            )
            .frame(minWidth: 760, minHeight: 520)
            .padding(20)
        }
    }

    private var selectedBannerId: Binding<String?> {
        Binding(
            get: {
                let available = store.bannerDetails.map(\.id)
                return available.contains(selectedBanner ?? "") ? selectedBanner : available.first
            },
            set: { selectedBanner = $0 }
        )
    }

    private var selectedDetail: WishBannerDetail? {
        let id = selectedBannerId.wrappedValue
        return store.bannerDetails.first { $0.id == id }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            PageHeader(
                title: "祈愿记录",
                subtitle: store.selectedRole.map { "\($0.nickname) · UID \($0.uid)" } ?? "请先登录账号"
            )
            Button("同步记录", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
                Task { await store.syncWishes() }
            }
            .buttonStyle(.glassProminent)
            .disabled(store.wishOperation != nil)

            Button("详细记录", systemImage: "tablecells") { showsHistory = true }
                .buttonStyle(.glass)
                .disabled(store.wishes.isEmpty || store.wishOperation != nil)

            Menu {
                Button("导入 UIGF", systemImage: "square.and.arrow.down") { importFile() }
                Button("导出 UIGF", systemImage: "square.and.arrow.up") { exportFile() }
                    .disabled(store.wishes.isEmpty)
                Divider()
                Button("升级旧版 UIGF", systemImage: "arrow.up.doc") { openUIGFUpgrader() }
                Divider()
                Button("清空全部记录", systemImage: "trash", role: .destructive) { confirmsClear = true }
                    .disabled(store.wishes.isEmpty)
            } label: {
                Label("更多", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .disabled(store.wishOperation != nil)
        }
    }
    private var workspace: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                HStack(alignment: .top, spacing: 14) {
                    detailPanel.frame(width: min(360, geometry.size.width * 0.38))
                    resultsPanel
                }
            } else {
                VStack(spacing: 14) {
                    detailPanel
                    resultsPanel
                }
            }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        BannerDetailCard(
            details: store.bannerDetails,
            selection: selectedBannerId
        )
    }

    private var resultsPanel: some View {
        WishResultsPanel(records: store.wishes)
    }

    private var loadingPlaceholder: some View {
        WishLoadingPlaceholder()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有祈愿记录", systemImage: "sparkles")
        } description: {
            Text("同步米游社记录或导入 UIGF 文件后，这里会展示保底进度与历史详情。")
        } actions: {
            Button("立即同步") { Task { await store.syncWishes() } }
                .buttonStyle(.glassProminent)
            Button("导入 UIGF") { importFile() }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.importUIGF(from: url) }
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "uigf-v4.2.json"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.exportUIGF(to: url) }
        }
    }

    private func openUIGFUpgrader() {
        NSWorkspace.shared.open(Self.uigfUpgraderURL)
    }
}
