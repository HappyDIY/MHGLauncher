import SwiftUI

struct CharacterBrowserView: View {
    @Bindable var store: LauncherStore
    @State private var elementFilter = CharacterElementFilter.all

    var body: some View {
        VStack(spacing: 0) {
            CharacterBrowserControls(
                searchText: $store.characterSearchText,
                elementFilter: $elementFilter,
                countText: countText,
                roleSummary: roleSummary
            )
            Divider()
            browserContent
        }
    }

    @ViewBuilder
    private var browserContent: some View {
        if filteredCharacters.isEmpty {
            ContentUnavailableView(
                "未找到角色",
                systemImage: "magnifyingglass",
                description: Text(emptyDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            characterGrid
        }
    }

    private var characterGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 142, maximum: 190), spacing: 12)],
                spacing: 12
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
                    .motionHover(.subtle)
                }
            }
            .padding(12)
        }
        .motionAnimation(.selection, value: store.selectedCharacterId)
    }

    private var filteredCharacters: [GameCharacter] {
        let values = store.characters.sorted { left, right in
            if left.rarity != right.rarity { return left.rarity > right.rarity }
            if left.level != right.level { return left.level > right.level }
            return left.name < right.name
        }
        return values.filter { character in
            elementFilter.matches(character) && matchesSearch(character)
        }
    }

    private func matchesSearch(_ character: GameCharacter) -> Bool {
        normalizedQuery.isEmpty
            || character.name.localizedCaseInsensitiveContains(normalizedQuery)
            || character.elementTitle.localizedCaseInsensitiveContains(normalizedQuery)
            || character.weaponName.localizedCaseInsensitiveContains(normalizedQuery)
    }

    private var normalizedQuery: String {
        store.characterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var countText: String {
        normalizedQuery.isEmpty && elementFilter == .all
            ? "\(store.characters.count) 位"
            : "\(filteredCharacters.count) / \(store.characters.count)"
    }

    private var emptyDescription: String {
        if !normalizedQuery.isEmpty {
            return "没有与“\(normalizedQuery)”匹配的角色"
        }
        return "当前账号没有\(elementFilter.title)角色"
    }

    private var roleSummary: String {
        store.selectedRole.map { "UID \($0.uid)" } ?? "未选择游戏角色"
    }

    private func isSelected(_ character: GameCharacter) -> Bool {
        store.selectedCharacterId == character.avatarId
    }
}
