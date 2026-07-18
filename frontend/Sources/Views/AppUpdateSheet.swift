import SwiftUI

struct AppUpdateSheet: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MHGLauncher \(manifest.version)").font(.title2.weight(.semibold))
                    Text("当前版本 \(store.currentAppVersion)").foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("更新日志").font(.headline)
            ScrollView { Text(manifest.changelog).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: 120, maxHeight: 260)
            if let error = store.appUpdate.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLiveRegion(.assertive)
            }
            HStack {
                Spacer()
                Button("以后再说") { store.appUpdate.showsSheet = false }
                    .disabled(store.appUpdate.isDownloading)
                Button {
                    Task { await store.downloadAppUpdate() }
                } label: {
                    if store.appUpdate.isDownloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("下载并打开", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.appUpdate.isDownloading)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var manifest: AppUpdateManifest {
        store.appUpdate.manifest!
    }
}
