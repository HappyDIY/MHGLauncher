import SwiftUI

struct AccountView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "账号",
                subtitle: "国服米游社账号与绑定角色"
            )
            if let account = store.account {
                accountCard(account)
                rolesCard
                Button("退出登录", role: .destructive) {
                    Task { await store.logout() }
                }
                .buttonStyle(.glass)
            } else {
                loginCard
            }
            Spacer()
        }
    }

    private func accountCard(_ account: Account) -> some View {
        GlassCard("当前账号", icon: "person.crop.circle.fill") {
            Text(account.nickname)
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
                        Text("\(role.region) · UID \(role.uid)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Lv.\(role.level)")
                    if role.selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
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
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 90))
                        .frame(width: 200, height: 200)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("使用米游社 App 扫描二维码")
                        .font(.title3.bold())
                    Text(loginStatus)
                        .foregroundStyle(.secondary)
                    Button(store.qrSession == nil ? "生成二维码" : "重新生成") {
                        Task { await store.beginQRLogin() }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(store.isBusy)
                }
            }
        }
    }

    private var loginStatus: String {
        switch store.qrSession?.status {
        case "created": "等待扫码"
        case "scanned": "已扫码，请在手机上确认"
        case "confirmed": "登录成功"
        case "expired": "二维码已过期"
        default: "凭据将安全保存在 macOS 钥匙串"
        }
    }
}

