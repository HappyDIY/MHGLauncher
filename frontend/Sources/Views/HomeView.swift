import SwiftUI

struct HomeView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isDebugMode {
                    debugBanner.motionEntrance(.emphasis)
                }
                if Self.shouldShowPredownloadBanner(store.gameState) {
                    predownloadBanner
                        .motionEntrance(order: 1)
                }
                PageHeader(
                    title: "欢迎回来",
                    subtitle: welcomeSubtitle
                )
                .motionEntrance(order: 2)
                HStack(alignment: .top, spacing: 16) {
                    gameCard
                        .motionScrollAppearance()
                        .motionEntrance(order: 3)
                    noteCard
                        .motionScrollAppearance()
                        .motionEntrance(order: 4)
                }
                HStack(alignment: .top, spacing: 16) {
                    wishCard
                        .motionScrollAppearance()
                        .motionEntrance(order: 5)
                    accountCard
                        .motionScrollAppearance()
                        .motionEntrance(order: 6)
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

    nonisolated static func shouldShowPredownloadBanner(_ state: GameState?) -> Bool {
        state?.hasPendingPredownload == true && state?.status != .notInstalled
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

    private var predownloadBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 34, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("原神 \(store.gameState?.predownloadVersion ?? "") 预下载已开放")
                    .font(.title3.bold())
                Text("提前下载新版本资源，正式开服后可更快完成更新")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
            Spacer(minLength: 12)
            Button {
                Task { await store.startGameJob(.predownload) }
            } label: {
                if store.pendingGameJobKind == .predownload {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在准备预下载")
                    }
                } else {
                    Label("预下载", systemImage: "arrow.down")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .motionHover(.prominent)
            .disabled(store.pendingGameJobKind != nil || store.gameState?.canStartPredownload != true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("predownload-banner")
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
            let summary = store.wishStatistics.reduce(into: (total: 0, fiveStars: 0)) {
                $0.total += $1.total
                $0.fiveStars += $1.fiveStarCount
            }
            HStack(spacing: 28) {
                MetricView(value: "\(summary.total)", label: "总抽数")
                MetricView(value: "\(summary.fiveStars)", label: "五星")
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
