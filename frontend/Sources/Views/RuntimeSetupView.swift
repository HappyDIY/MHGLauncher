import SwiftUI

struct RuntimeSetupView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "MHGLauncher", subtitle: "正在准备本地运行环境")
            GlassCard("本地服务运行时", icon: icon) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(title)
                            .font(.headline)
                        Spacer()
                        if store.isInstallingCoreRuntime || store.backend.isStarting {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let progress = store.runtimeProgress, progress.scope == .core {
                        ProgressView(value: progress.fraction)
                            .motionAnimation(.progress, value: progress.fraction)
                        Text(progress.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let error = store.runtimeErrorMessage ?? store.backend.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                    if store.runtimeErrorMessage != nil || store.backend.errorMessage != nil {
                        Button("重试") {
                            Task { await store.retryBootstrap() }
                        }
                        .buttonStyle(.borderedProminent)
                        .motionHover(.prominent)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var title: String {
        if store.backend.isStarting { return "正在启动本地服务" }
        if store.isInstallingCoreRuntime { return "正在下载 Node.js 与生产依赖" }
        if store.runtimeErrorMessage != nil || store.backend.errorMessage != nil { return "本地运行环境未就绪" }
        return "正在检查运行环境"
    }

    private var icon: String {
        store.runtimeErrorMessage == nil && store.backend.errorMessage == nil
            ? "arrow.down.circle"
            : "exclamationmark.triangle"
    }
}
