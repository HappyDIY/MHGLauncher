import SwiftUI

struct GameResourceActionButtons: View {
    @Bindable var store: LauncherStore

    var body: some View {
        HStack {
            action(.install, title: "安装", enabled: store.gameState?.status == .notInstalled)
            action(.update, title: "更新", enabled: store.gameState?.status == .updateAvailable)
            Spacer()
        }
        .buttonStyle(.glassProminent)
    }

    private func action(_ kind: JobKind, title: String, enabled: Bool) -> some View {
        Button {
            Task { await store.startGameJob(kind) }
        } label: {
            HStack(spacing: 6) {
                if store.pendingGameJobKind == kind {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在准备\(title)…")
                } else {
                    Text(title)
                }
            }
            .contentTransition(.opacity)
        }
        .motionAnimation(.selection, value: store.pendingGameJobKind)
        .motionHover(.prominent)
        .disabled(!enabled || store.pendingGameJobKind != nil)
    }
}
