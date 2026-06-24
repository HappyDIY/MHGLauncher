import SwiftUI

struct HomeView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isDebugMode {
                    debugBanner.motionEntrance(.emphasis)
                }
                PageHeader(
                    title: "欢迎回来",
                    subtitle: welcomeSubtitle
                )
                .motionEntrance(order: 1)
                HStack(alignment: .top, spacing: 16) {
                    gameCard
                        .motionScrollAppearance()
                        .motionEntrance(order: 2)
                    noteCard
                        .motionScrollAppearance()
                        .motionEntrance(order: 3)
                }
                HStack(alignment: .top, spacing: 16) {
                    wishCard
                        .motionScrollAppearance()
                        .motionEntrance(order: 4)
                    accountCard
                        .motionScrollAppearance()
                        .motionEntrance(order: 5)
                }
            }
        }
    }

    private var isDebugMode: Bool {
        Self.isDebugMode(environment: ProcessInfo.processInfo.environment)
    }

    nonisolated static func isDebugMode(environment: [String: String]) -> Bool {
        environment["MHG_DEBUG_MODE"] == "1"
    }

    private var debugBanner: some View {
        Label("调试模式", systemImage: "hammer.fill")
            .font(.title2.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("debug-mode-banner")
    }

    private var welcomeSubtitle: String {
        store.account?.displayName(role: store.selectedRole)
            ?? "登录米游社后同步旅行数据"
    }

    private var gameCard: some View {
        GlassCard("游戏", icon: "gamecontroller.fill") {
            MetricView(
                value: store.gameState?.availableVersion.nonempty ?? "未知",
                label: "最新版本"
            )
            Text(store.gameState?.status.title ?? "正在检查")
                .foregroundStyle(.secondary)
            GameLaunchControls(store: store)
        }
    }

    private var noteCard: some View {
        GlassCard("实时便笺", icon: "note.text") {
            if let note = store.dailyNote {
                HStack(spacing: 28) {
                    MetricView(
                        value: "\(note.currentResin)/\(note.maxResin)",
                        label: "原粹树脂"
                    )
                    MetricView(
                        value: "\(note.finishedTasks)/\(note.totalTasks)",
                        label: "每日委托"
                    )
                }
            } else {
                Text("暂无便笺数据")
                    .foregroundStyle(.secondary)
            }
        }
        .motionAnimation(.content, value: store.dailyNote != nil)
    }

    private var wishCard: some View {
        GlassCard("祈愿记录", icon: "sparkles") {
            let total = store.wishStatistics.reduce(0) { $0 + $1.total }
            let fiveStars = store.wishStatistics.reduce(0) { $0 + $1.fiveStarCount }
            HStack(spacing: 28) {
                MetricView(value: "\(total)", label: "总抽数")
                MetricView(value: "\(fiveStars)", label: "五星")
            }
        }
    }

    private var accountCard: some View {
        GlassCard("账号", icon: "person.crop.circle") {
            Text(store.selectedRole?.nickname ?? "未选择角色")
                .font(.title3.bold())
            Text(store.selectedRole.map { "UID \($0.uid) · Lv.\($0.level)" } ?? "请先扫码登录")
                .foregroundStyle(.secondary)
        }
    }
}
