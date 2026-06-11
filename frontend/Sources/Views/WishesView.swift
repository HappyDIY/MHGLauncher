import AppKit
import SwiftUI

struct WishesView: View {
    @Bindable var store: LauncherStore
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                PageHeader(
                    title: "祈愿记录",
                    subtitle: store.selectedRole.map { "UID \($0.uid)" } ?? "请先登录账号"
                )
                Spacer()
                Button("同步") {
                    Task { await store.syncWishes() }
                }
                .buttonStyle(.glassProminent)
                .disabled(store.wishOperation != nil)
                Button("导入 UIGF") { importFile() }
                    .buttonStyle(.glass)
                    .disabled(store.wishOperation != nil)
                Button("导出 UIGF") { exportFile() }
                    .buttonStyle(.glass)
                    .disabled(store.wishOperation != nil)
                Button("清空记录", systemImage: "trash", role: .destructive) {
                    confirmsClear = true
                }
                .buttonStyle(.glass)
                .disabled(store.wishOperation != nil || store.wishes.isEmpty)
            }
            if !store.wishStatistics.isEmpty {
                statistics
            }
            GlassCard("历史记录", icon: "clock.arrow.circlepath") {
                Table(store.wishes) {
                    TableColumn("时间") { item in
                        Text(item.time.formatted(date: .abbreviated, time: .shortened))
                    }
                    TableColumn("名称", value: \.name)
                    TableColumn("类型", value: \.itemType)
                    TableColumn("星级") { item in
                        Text(String(repeating: "★", count: item.rank))
                            .foregroundStyle(item.rank == 5 ? .orange : .secondary)
                    }
                    TableColumn("卡池", value: \.gachaType)
                }
                .frame(minHeight: 360)
            }
        }
        .overlay {
            if let operation = store.wishOperation {
                WishOperationOverlay(operation: operation) {
                    store.wishOperation = nil
                }
            }
        }
        .animation(.spring(duration: 0.45), value: store.wishOperation?.id)
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
    }

    private var statistics: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(store.wishStatistics) { item in
                    GlassCard(poolName(item.gachaType), icon: "sparkles") {
                        HStack(spacing: 22) {
                            MetricView(value: "\(item.total)", label: "总抽数")
                            MetricView(value: "\(item.fiveStarCount)", label: "五星")
                            MetricView(
                                value: "\(item.pullsSinceFiveStar)",
                                label: "距上次五星"
                            )
                        }
                    }
                    .frame(width: 330)
                }
            }
        }
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

    private func poolName(_ type: String) -> String {
        switch type {
        case "100": "新手祈愿"
        case "200": "常驻祈愿"
        case "301": "角色活动祈愿"
        case "302": "武器活动祈愿"
        default: "卡池 \(type)"
        }
    }
}
