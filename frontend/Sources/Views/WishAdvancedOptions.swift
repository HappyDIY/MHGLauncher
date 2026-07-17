import SwiftUI

struct WishAdvancedOptions: View {
    @Bindable var store: LauncherStore
    @State private var showsURLImport = false
    @State private var gachaURL = ""

    var body: some View {
        if store.account == nil {
            Menu {
                Button("通过抽卡 URL 导入", systemImage: "link.badge.plus") {
                    showsURLImport = true
                }
            } label: {
                Label("高级选项", systemImage: "gearshape.2")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .motionHover()
            .disabled(store.isWishOperationActive)
            .alert("通过抽卡 URL 导入", isPresented: $showsURLImport) {
                TextField("粘贴完整抽卡 URL", text: $gachaURL)
                Button("取消", role: .cancel) {}
                Button("导入") {
                    let value = gachaURL
                    gachaURL = ""
                    Task { await store.importWishes(fromGachaURL: value) }
                }
                .disabled(gachaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("推荐先登录米游社账号以自动同步。仅在无法登录时手动粘贴包含 authkey 的完整 URL。")
            }
        }
    }
}
