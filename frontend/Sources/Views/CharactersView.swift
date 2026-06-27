import SwiftUI

struct CharactersView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "我的角色", subtitle: selectedUID)
                HStack {
                    Button {
                        Task { await store.refreshCharacters() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Text("\(store.value.characters.count) 名角色")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(store.value.characters) { character in
                        GlassCard(character.name, icon: "person.crop.square") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    MetricView(value: "\(character.level)", label: "等级")
                                    Spacer()
                                    MetricView(value: "\(character.constellation)", label: "命座")
                                }
                                Text(character.element)
                                    .foregroundStyle(.secondary)
                                Text(character.weaponName.nonempty ?? "未同步武器")
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .task { await store.loadValueData() }
        .motionEntrance(.content)
    }

    private var selectedUID: String {
        store.selectedRole.map { "UID \($0.uid)" } ?? "未选择角色"
    }
}
