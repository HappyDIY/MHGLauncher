import SwiftUI

struct RuntimeSetupView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "MHGLauncher", subtitle: "正在准备本地运行环境")
            GlassCard("Launcher Core", icon: icon) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .accessibilityLiveRegion(.polite)
                        Spacer()
                        if store.isInstallingCoreRuntime || store.coreHost.state == .initializing {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if let progress = store.runtimeProgress, progress.scope == .core {
                        ProgressView(value: progress.fraction)
                            .accessibilityLabel("Launcher Core 初始化进度")
                            .motionAnimation(.progress, value: progress.fraction)
                        Text(progress.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let error = store.runtimeErrorMessage ?? coreError {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityLiveRegion(.assertive)
                    }
                    if store.runtimeErrorMessage != nil || coreError != nil {
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
        if store.coreHost.state == .initializing { return "正在初始化 Launcher Core" }
        if store.isInstallingCoreRuntime { return "正在准备 Launcher Core" }
        if store.runtimeErrorMessage != nil || coreError != nil { return "Launcher Core 未就绪" }
        return "正在检查运行环境"
    }

    private var icon: String {
        store.runtimeErrorMessage == nil && coreError == nil
            ? "arrow.down.circle"
            : "exclamationmark.triangle"
    }

    private var coreError: String? {
        if case .failed(_, let message) = store.coreHost.state { return message }
        return nil
    }
}
