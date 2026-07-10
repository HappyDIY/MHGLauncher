import SwiftUI

struct CharacterDetailView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            if let character = store.selectedCharacter {
                VStack(alignment: .leading, spacing: 16) {
                    CharacterHeroCard(character: character) {
                        Task { await store.refreshSelectedCharacterDetail() }
                    }
                    CharacterPropertySection(character: character)
                    CharacterRecommendationSection(character: character)
                    CharacterReliquarySection(character: character)
                }
                .frame(maxWidth: 860, alignment: .leading)
                .motionAnimation(.content, value: character.avatarId)
                .task(id: character.avatarId) {
                    if !character.detailReady {
                        await store.refreshCharacterDetail(character)
                    }
                }
            } else {
                ContentUnavailableView("未选择角色", systemImage: "person.crop.square")
            }
        }
    }
}

struct CharacterIcon: View {
    let character: GameCharacter
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10)
                .fill(rarityColor.opacity(0.18))
            CachedAsyncImage(url: character.iconUrl) {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(rarityColor)
            }
            .padding(5)
            Text("\(character.rarity)")
                .font(.caption2.bold())
                .padding(.horizontal, 5)
                .background(.black.opacity(0.24), in: .capsule)
        }
        .frame(width: size, height: size)
        .overlay(rarityColor.opacity(0.4), in: .rect(cornerRadius: 10).stroke())
    }

    private var rarityColor: Color {
        character.rarity >= 5 ? .orange : .purple
    }
}

private struct CharacterHeroCard: View {
    let character: GameCharacter
    let refreshDetail: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [.black.opacity(0.55), elementColor.opacity(0.55), .black.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .trailing) {
                CharacterIcon(character: character, size: 160)
                    .opacity(0.32)
                    .padding(28)
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    CharacterIcon(character: character, size: 82)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(character.name)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("Lv.\(character.level) · \(character.elementTitle) · 好感 \(character.fetter)")
                            .foregroundStyle(.white.opacity(0.82))
                        StarRow(count: character.rarity)
                    }
                    Spacer()
                    Button(action: refreshDetail) {
                        Label("详情", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                HStack(spacing: 12) {
                    CharacterMetric(value: "\(character.constellation)", label: "命座")
                    CharacterMetric(value: character.weaponName.nonempty ?? "未同步", label: "武器")
                    CharacterMetric(value: "\(character.weaponLevel)", label: "武器等级")
                }
                CharacterSkillStrip(skills: character.payload?.skills ?? [])
                CharacterConstellationStrip(values: character.payload?.constellations, active: character.constellation)
            }
            .padding(18)
        }
        .frame(minHeight: 280)
        .clipShape(.rect(cornerRadius: 14))
    }

    private var elementColor: Color {
        switch character.elementTitle {
        case "火": .red
        case "水": .blue
        case "风": .teal
        case "雷": .purple
        case "草": .green
        case "冰": .cyan
        case "岩": .yellow
        default: .gray
        }
    }
}

private struct CharacterMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
    }
}

private struct StarRow: View {
    let count: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(count, 0), id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
    }
}
