import SwiftUI

struct CharacterDetailView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            if let character = store.selectedCharacter {
                LazyVStack(spacing: 0) {
                    CharacterHeroBand(character: character, isBusy: store.isBusy) {
                        Task { await store.refreshSelectedCharacterDetail() }
                    }
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    VStack(alignment: .leading, spacing: 26) {
                        if store.isBusy, !character.detailReady {
                            ProgressView("正在同步角色详情…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                        CharacterGrowthSection(character: character)
                        CharacterPropertySection(character: character)
                        CharacterRecommendationSection(character: character)
                        CharacterReliquarySection(character: character)
                    }
                    .padding(24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .motionAnimation(.content, value: character.avatarId)
                .task(id: character.avatarId) {
                    if !character.detailReady {
                        await store.refreshCharacterDetail(character)
                    }
                }
            } else {
                ContentUnavailableView(
                    "选择一位角色",
                    systemImage: "person.crop.square",
                    description: Text("从左侧角色库查看等级、武器与养成详情")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
