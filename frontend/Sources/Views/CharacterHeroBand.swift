import SwiftUI

struct CharacterHeroBand: View {
    let character: GameCharacter
    let isBusy: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            identity
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    CharacterWeaponOverview(character: character)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().frame(height: 54)
                    CharacterConstellationOverview(character: character)
                        .frame(width: 180, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 16) {
                    CharacterWeaponOverview(character: character)
                    Divider()
                    CharacterConstellationOverview(character: character)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 22) {
            CharacterIcon(character: character, size: 136)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    CharacterElementIcon(character: character, size: 17)
                    Text("\(character.elementTitle)元素")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(character.elementColor)
                Text(character.name)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 18) {
                    CharacterIdentityStat(value: "\(character.level)", label: "等级")
                    CharacterIdentityStat(value: "\(character.fetter)", label: "好感")
                    CharacterIdentityStat(value: "\(character.rarity)", label: "星级")
                }
            }
            Spacer(minLength: 6)
            Button(action: refresh) {
                Group {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .disabled(isBusy)
            .help("刷新角色详情")
            .accessibilityLabel("刷新角色详情")
            .motionHover()
        }
    }
}

private struct CharacterIdentityStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CharacterWeaponOverview: View {
    let character: GameCharacter

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(0.06))
                CachedAsyncImage(url: character.payload?.weapon?.icon) {
                    Image(systemName: "sword")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .padding(7)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(character.weaponName.nonempty ?? "未同步武器")
                    .font(.headline)
                    .lineLimit(1)
                    .help(character.weaponName)
                Text(weaponDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var weaponDetail: String {
        if let rank = character.payload?.weapon?.affixLevel, rank > 0 {
            return "武器等级 \(character.weaponLevel) · 精炼 \(rank)"
        }
        return "武器等级 \(character.weaponLevel)"
    }
}

private struct CharacterConstellationOverview: View {
    let character: GameCharacter

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(character.constellation)")
                    .font(.title2.weight(.bold).monospacedDigit())
                Text("/ 6 命")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(index < character.constellation
                            ? character.elementColor
                            : Color.secondary.opacity(0.2))
                        .frame(width: 20, height: 5)
                }
            }
            Text("命之座激活进度")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("已激活 \(character.constellation) 个命之座")
    }
}
