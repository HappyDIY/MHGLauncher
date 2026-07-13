import SwiftUI

struct RuntimeStatusView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(statusText, systemImage: store.gameRuntimeReady ? "checkmark.circle" : "arrow.down.circle")
                    .foregroundStyle(store.gameRuntimeReady ? .green : .secondary)
                    .accessibilityLiveRegion(.polite)
                Spacer()
                if store.isInstallingGameRuntime {
                    ProgressView().controlSize(.small)
                } else if !store.gameRuntimeReady {
                    Button("安装运行时") {
                        Task { await install() }
                    }
                    .buttonStyle(.glass)
                    .motionHover()
                }
            }
            if let progress = store.runtimeProgress, progress.scope == .game {
                ProgressView(value: progress.fraction)
                    .accessibilityLabel("游戏运行组件安装进度")
                    .motionAnimation(.progress, value: progress.fraction)
                Text(progress.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        if store.gameRuntimeReady { return "Wine 运行组件已就绪" }
        if store.isInstallingGameRuntime { return "正在安装 Wine 运行组件" }
        return "需要下载 Wine、DXMT、MSync 与宿主组件"
    }

    private func install() async {
        await store.perform {
            try await store.ensureGameRuntime()
        }
    }
}
