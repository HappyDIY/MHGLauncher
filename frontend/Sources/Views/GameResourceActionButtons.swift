import SwiftUI

struct GameResourceActionButtons: View {
    @Bindable var store: LauncherStore
    @State private var disclaimerJobKind: JobKind?

    var body: some View {
        HStack {
            action(
                .install,
                title: store.gameState?.status == .damaged ? "继续安装" : "安装",
                enabled: store.gameState.map { [.notInstalled, .damaged].contains($0.status) } == true
            )
            if store.gameState?.hasPendingPredownload == true && store.gameState?.status != .notInstalled {
                action(.predownload, title: "预下载", enabled: store.gameState?.canStartPredownload == true)
            }
            action(.update, title: "更新", enabled: store.gameState?.status == .updateAvailable)
            action(.verify, title: "校验", enabled: store.gameState.map { [.ready, .updateAvailable].contains($0.status) } == true)
            Spacer()
        }
        .buttonStyle(.glassProminent)
        .sheet(item: $disclaimerJobKind) { kind in
            FinalDisclaimerView(allowsCancellation: true) {
                Task { await store.startGameJob(kind) }
            }
        }
    }

    private func action(_ kind: JobKind, title: String, enabled: Bool) -> some View {
        Button {
            if requiresDisclaimer(kind), FinalDisclaimerConsent.shouldPresent() {
                disclaimerJobKind = kind
            } else {
                Task { await store.startGameJob(kind) }
            }
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

    private func requiresDisclaimer(_ kind: JobKind) -> Bool {
        [.install, .update, .verify].contains(kind)
    }
}

extension JobKind: Identifiable {
    var id: String { rawValue }
}
