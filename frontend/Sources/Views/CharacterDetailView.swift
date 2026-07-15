import SwiftUI

struct CharacterDetailView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView {
            if let character = store.selectedCharacter {
                VStack(alignment: .leading, spacing: 16) {
                    CharacterHeroCard(character: character, isBusy: store.isBusy) {
                        Task { await store.refreshSelectedCharacterDetail() }
                    }
                    if store.isBusy, !character.detailReady {
                        ProgressView("正在同步角色详情…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    CharacterPropertySection(character: character)
                    CharacterRecommendationSection(character: character)
                    CharacterReliquarySection(character: character)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
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

struct CharacterIcon: View {
    let character: GameCharacter
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10)
                .fill(character.rarityColor.opacity(0.16))
            CachedAsyncImage(url: character.iconUrl) {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(character.rarityColor)
            }
            .padding(5)
            Label("\(character.rarity)", systemImage: "star.fill")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.58), in: .capsule)
        }
        .frame(width: size, height: size)
        .overlay(character.rarityColor.opacity(0.45), in: .rect(cornerRadius: 10).stroke())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.name)，\(character.rarity) 星")
    }
}

private struct CharacterHeroCard: View {
    let character: GameCharacter
    let isBusy: Bool
    let refreshDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identity
            Divider()
            HStack(spacing: 10) {
                CharacterMetric(icon: "moon.stars", value: "\(character.constellation) 命", label: "命之座")
                Divider().frame(height: 44)
                CharacterMetric(
                    icon: "sword",
                    value: character.weaponName.nonempty ?? "未同步",
                    label: "武器"
                )
                Divider().frame(height: 44)
                CharacterMetric(icon: "arrow.up.right", value: "Lv.\(character.weaponLevel)", label: "武器等级")
            }
            if !(character.payload?.skills ?? []).isEmpty {
                DetailStripLabel(title: "天赋等级", icon: "sparkles")
                CharacterSkillStrip(skills: character.payload?.skills ?? [])
            }
            DetailStripLabel(title: "命之座", icon: "moon.stars")
            CharacterConstellationStrip(
                values: character.payload?.constellations,
                active: character.constellation
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 15) {
            CharacterIcon(character: character, size: 96)
            VStack(alignment: .leading, spacing: 7) {
                Text(character.name)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(character.elementTitle, systemImage: character.elementSymbol)
                        .foregroundStyle(character.elementColor)
                    Text("Lv.\(character.level)")
                    Text("好感 \(character.fetter)")
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                StarRow(count: character.rarity)
            }
            Spacer(minLength: 8)
            Button(action: refreshDetail) {
                Group {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .disabled(isBusy)
            .help("刷新角色详情")
            .accessibilityLabel("刷新角色详情")
            .motionHover()
        }
    }
}

private struct DetailStripLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct CharacterMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .help(value)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) 星角色")
    }
}
