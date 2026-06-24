import SwiftUI

struct AccountView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "账号",
                subtitle: "国服米游社账号与绑定角色"
            )
            .motionEntrance(order: 0)
            if let account = store.account {
                accountCard(account).motionEntrance(order: 1)
                rolesCard.motionEntrance(order: 2)
                Button("退出登录", role: .destructive) {
                    Task { await store.logout() }
                }
                .buttonStyle(.glass)
                .motionEntrance(order: 3)
            } else {
                loginCard.motionEntrance(order: 1)
            }
            Spacer()
        }
        .motionAnimation(.emphasis, value: store.account?.aid)
    }

    private func accountCard(_ account: Account) -> some View {
        GlassCard("当前账号", icon: "person.crop.circle.fill") {
            Text(account.displayName(role: store.selectedRole))
                .font(.title2.bold())
            Text("账号 ID \(account.aid)")
                .foregroundStyle(.secondary)
        }
    }

    private var rolesCard: some View {
        GlassCard("原神角色", icon: "person.2") {
            ForEach(store.roles) { role in
                HStack {
                    VStack(alignment: .leading) {
                        Text(role.nickname)
                            .font(.headline)
                        Text("\(role.regionName) · UID \(role.uid)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Lv.\(role.level)")
                    if role.selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .motionSymbolBounce(value: role.selected)
                    }
                }
                .motionEntrance(order: store.roles.firstIndex { $0.id == role.id } ?? 0)
            }
        }
    }

    private var loginCard: some View {
        GlassCard("扫码登录", icon: "qrcode") {
            HStack(spacing: 24) {
                if let url = store.qrSession?.url,
                   let image = QRCodeImage.make(url) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 180, height: 180)
                        .padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .motionTransition(.emphasis)
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 90))
                        .frame(width: 200, height: 200)
                        .foregroundStyle(.secondary)
                        .motionTransition(.emphasis)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("使用米游社 App 扫描二维码")
                        .font(.title3.bold())
                    Text(loginStatus)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .motionAnimation(.content, value: loginStatus)
                    Button(store.qrSession == nil ? "生成二维码" : "重新生成") {
                        Task { await store.beginQRLogin() }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(store.isBusy || !store.backend.isReady)
                }
            }
            .motionAnimation(.emphasis, value: store.qrSession?.url)
        }
    }

    private var loginStatus: String {
        switch store.qrSession?.status {
        case "created": "等待扫码"
        case "scanned": "已扫码，请在手机上确认"
        case "confirmed": "登录成功"
        case "expired": "二维码已过期"
        default:
            if store.backend.isStarting {
                "正在启动本地服务…"
            } else if let error = store.backend.errorMessage {
                error
            } else {
                "凭据将安全保存在 macOS 钥匙串"
            }
        }
    }
}
