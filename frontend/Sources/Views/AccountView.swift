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
                accountsCard.motionEntrance(order: 2)
                rolesCard.motionEntrance(order: 3)
                HStack {
                    Button("添加账号") {
                        Task { await store.beginQRLogin() }
                    }
                    .buttonStyle(.glassProminent)
                    .motionHover(.prominent)
                    Button("退出当前账号", role: .destructive) {
                        Task { await store.logout() }
                    }
                    .buttonStyle(.glass)
                    .motionHover(.destructive)
                }
                .motionEntrance(order: 4)
            } else {
                AccountLoginView(store: store).motionEntrance(order: 1)
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
                Button {
                    Task { await store.selectRole(role) }
                } label: {
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .motionHover(role.selected ? .selection : .subtle)
                .motionEntrance(order: store.roles.firstIndex { $0.id == role.id } ?? 0)
            }
        }
    }

    private var accountsCard: some View {
        GlassCard("已登录账号", icon: "person.2.circle") {
            ForEach(store.accounts, id: \.aid) { account in
                Button {
                    Task { await store.selectAccount(account) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.displayName(role: nil))
                                .font(.headline)
                            Text("账号 ID \(account.aid)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if account.selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .motionHover(account.selected ? .selection : .subtle)
            }
        }
    }

}
