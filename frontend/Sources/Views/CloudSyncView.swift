import SwiftUI

struct CloudSyncView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "云同步", subtitle: "抽卡 URL 认证与祈愿记录云端备份")
            GlassCard("米游社账号认证", icon: "person.badge.key") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("登录后将自动提取当前角色的临时抽卡 URL，并直接交给云端完成鉴权。")
                        .foregroundStyle(.secondary)
                    HStack {
                        if let role = store.selectedRole, store.account != nil {
                            Button {
                                Task { await store.loginCloud() }
                            } label: {
                                Label(
                                    store.value.cloudSession?.uid == role.uid ? "重新鉴权" : "使用当前账号鉴权",
                                    systemImage: "checkmark.seal"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isBusy)
                        } else {
                            Button("前往账号登录", systemImage: "person.crop.circle.badge.plus") {
                                store.selectedDestination = .account
                            }
                            .buttonStyle(.borderedProminent)
                        }
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
                    .disabled(!canSync)
                    Button {
                        Task { await store.retrieveCloudWishes() }
                    } label: {
                        Label("取回", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!canSync)
                    Spacer()
                    Text(store.value.cloudMessage.nonempty ?? "等待操作")
                        .foregroundStyle(.secondary)
                        .accessibilityLiveRegion(.polite)
                }
            }
            Spacer()
        }
        .motionEntrance(.content)
    }

    private var canSync: Bool {
        guard let role = store.selectedRole, let session = store.value.cloudSession else { return false }
        return role.uid == session.uid && !store.isBusy
    }
}
