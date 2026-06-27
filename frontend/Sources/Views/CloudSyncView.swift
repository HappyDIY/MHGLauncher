import SwiftUI

struct CloudSyncView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "云同步", subtitle: "抽卡 URL 认证与祈愿记录云端备份")
            GlassCard("认证", icon: "link") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("抽卡 URL", text: $store.value.cloudLoginURL)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            Task { await store.loginCloud() }
                        } label: {
                            Label("认证登录", systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.borderedProminent)
                        if let session = store.value.cloudSession {
                            Text("UID \(session.uid)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            GlassCard("同步", icon: "icloud") {
                HStack(spacing: 12) {
                    Button {
                        Task { await store.uploadCloudWishes() }
                    } label: {
                        Label("上传", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Task { await store.retrieveCloudWishes() }
                    } label: {
                        Label("取回", systemImage: "square.and.arrow.down")
                    }
                    Spacer()
                    Text(store.value.cloudMessage.nonempty ?? "等待操作")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .motionEntrance(.content)
    }
}
