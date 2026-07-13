import SwiftUI

struct CharactersView: View {
    @Bindable var store: LauncherStore
    @State private var layout = CharacterLayout.list

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "我的角色", subtitle: selectedUID)
            toolbar
            if store.characters.isEmpty {
                CharacterEmptyView(isBusy: store.isBusy) {
                    Task { await store.refreshCharacters() }
                }
            } else {
                content
            }
        }
        .task {
            await store.loadCharacters()
            if store.characters.isEmpty { await store.refreshCharacters() }
        }
        .motionEntrance(.content)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("布局", selection: $layout) {
                Label("列表", systemImage: "sidebar.left").tag(CharacterLayout.list)
                Label("网格", systemImage: "square.grid.2x2").tag(CharacterLayout.grid)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            TextField("搜索角色、元素或武器", text: $store.characterSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Spacer()
            Text("\(filteredCharacters.count) / \(store.characters.count)")
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Button {
                Task { await store.refreshCharacters() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isBusy)
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                switch layout {
                case .list: characterList
                case .grid: characterGrid
                }
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
            CharacterDetailView(store: store)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var characterList: some View {
        List(filteredCharacters, selection: $store.selectedCharacterId) { character in
            CharacterListRow(character: character)
                .tag(character.avatarId)
                .contentShape(.rect)
                .onTapGesture { store.selectCharacter(character) }
        }
        .listStyle(.sidebar)
        .clipShape(.rect(cornerRadius: 12))
        .motionAnimation(.selection, value: store.selectedCharacterId)
    }

    private var characterGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(filteredCharacters) { character in
                    Button {
                        store.selectCharacter(character)
                    } label: {
                        CharacterGridTile(
                            character: character,
                            selected: store.selectedCharacterId == character.avatarId
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.selectedCharacterId == character.avatarId ? .isSelected : [])
                    .accessibilityValue(store.selectedCharacterId == character.avatarId ? "已选择" : "未选择")
                    .motionHover(.selection)
                }
            }
            .padding(2)
        }
    }

    private var filteredCharacters: [GameCharacter] {
        let query = store.characterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = store.characters.sorted { left, right in
            if left.rarity != right.rarity { return left.rarity > right.rarity }
            if left.level != right.level { return left.level > right.level }
            return left.name < right.name
        }
        guard !query.isEmpty else { return values }
        return values.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.elementTitle.localizedCaseInsensitiveContains(query)
                || $0.weaponName.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedUID: String {
        store.selectedRole.map { "UID \($0.uid)" } ?? "未选择角色"
    }
}

private enum CharacterLayout { case list, grid }

private struct CharacterEmptyView: View {
    let isBusy: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.square.stack")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("暂无角色数据")
                .font(.title3.bold())
            Button(action: refresh) {
                Label("从米游社同步", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}

private struct CharacterListRow: View {
    let character: GameCharacter

    var body: some View {
        HStack(spacing: 12) {
            CharacterIcon(character: character, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("Lv.\(character.level) · \(character.elementTitle) · \(character.weaponName.nonempty ?? "未同步武器")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(character.constellation) 命")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CharacterGridTile: View {
    let character: GameCharacter
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CharacterIcon(character: character, size: 56)
                Spacer()
                Text("C\(character.constellation)")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.18), in: .capsule)
            }
            Text(character.name)
                .font(.headline)
                .lineLimit(1)
            Text("Lv.\(character.level) · \(character.elementTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(characterAccent.opacity(selected ? 0.24 : 0.12), in: .rect(cornerRadius: 12))
        .overlay(.quaternary, in: .rect(cornerRadius: 12).stroke(lineWidth: selected ? 2 : 1))
    }

    private var characterAccent: Color {
        character.rarity >= 5 ? .orange : .purple
    }
}
