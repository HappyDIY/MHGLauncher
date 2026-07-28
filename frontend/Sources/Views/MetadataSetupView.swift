import SwiftUI

struct MetadataSetupView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("正在准备游戏资料")
                .font(.title2.bold())
            progress
                .frame(maxWidth: 420)
            if let error = store.resourceSetupError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Button(
                    "重试", systemImage: "arrow.clockwise",
                    action: store.startInitialResourceRetry
                )
                .buttonStyle(.glassProminent)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    @ViewBuilder private var progress: some View {
        if let status, status.assetTotal > 0 {
            VStack(spacing: 8) {
                ProgressView(value: status.assetProgress)
                Text("\(status.assetCompleted) / \(status.assetTotal)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView()
                .controlSize(.large)
        }
    }

    private var status: ResourceSyncStatus? { store.value.resourceSyncStatus }
}
