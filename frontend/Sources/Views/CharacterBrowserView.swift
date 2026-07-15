import SwiftUI

enum CharacterLayout: Hashable {
    case list
    case grid
}

struct CharacterBrowserView: View {
    @Bindable var store: LauncherStore
    @Binding var layout: CharacterLayout

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            browserContent
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("角色")
                        .font(.headline)
                    Text(roleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索角色、元素或武器", text: $store.characterSearchText)
                    .textFieldStyle(.plain)
                if !normalizedQuery.isEmpty {
                    Button {
                        store.characterSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("清除搜索")
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .glassEffect(.regular.interactive(), in: .capsule)
            HStack(spacing: 8) {
                Picker("布局", selection: $layout) {
                    Label("列表", systemImage: "list.bullet").tag(CharacterLayout.list)
                    Label("网格", systemImage: "square.grid.2x2").tag(CharacterLayout.grid)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var browserContent: some View {
        if filteredCharacters.isEmpty {
            ContentUnavailableView(
                "未找到角色",
                systemImage: "magnifyingglass",
                description: Text("没有与“\(normalizedQuery)”匹配的角色")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch layout {
            case .list: characterList
            case .grid: characterGrid
            }
        }
    }

    private var characterList: some View {
        List(filteredCharacters, selection: $store.selectedCharacterId) { character in
            CharacterListRow(character: character)
                .tag(character.avatarId)
                .contentShape(.rect)
                .onTapGesture { store.selectCharacter(character) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .motionAnimation(.selection, value: store.selectedCharacterId)
    }

    private var characterGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 10)],
                spacing: 10
            ) {
                ForEach(filteredCharacters) { character in
                    Button {
                        store.selectCharacter(character)
                    } label: {
                        CharacterGridTile(
                            character: character,
                            selected: isSelected(character)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择角色 \(character.name)")
                    .accessibilityAddTraits(isSelected(character) ? .isSelected : [])
                    .accessibilityValue(isSelected(character) ? "已选择" : "未选择")
                    .motionHover(.selection)
                }
            }
            .padding(10)
        }
        .motionAnimation(.selection, value: store.selectedCharacterId)
    }

    private var filteredCharacters: [GameCharacter] {
        let values = store.characters.sorted { left, right in
            if left.rarity != right.rarity { return left.rarity > right.rarity }
            if left.level != right.level { return left.level > right.level }
            return left.name < right.name
        }
        guard !normalizedQuery.isEmpty else { return values }
        return values.filter {
            $0.name.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.elementTitle.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.weaponName.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    private var normalizedQuery: String {
        store.characterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var countText: String {
        normalizedQuery.isEmpty
            ? "\(store.characters.count) 位"
            : "\(filteredCharacters.count) / \(store.characters.count)"
    }

    private var roleSummary: String {
        store.selectedRole.map { "UID \($0.uid)" } ?? "未选择游戏角色"
    }

    private func isSelected(_ character: GameCharacter) -> Bool {
        store.selectedCharacterId == character.avatarId
    }
}
