import SwiftUI

struct CharacterGrowthSection: View {
    let character: GameCharacter

    @ViewBuilder
    var body: some View {
        let skills = character.payload?.skills ?? []
        if skills.isEmpty {
            SectionPanel(title: "命之座", icon: "moon.stars") {
                constellationStrip
            }
        } else {
            SectionPanel(title: "天赋与命座", icon: "sparkles") {
                subsectionTitle("天赋等级")
                CharacterSkillStrip(skills: skills)
                subsectionTitle("命之座")
                constellationStrip
            }
        }
    }

    private var constellationStrip: some View {
        CharacterConstellationStrip(
            values: character.payload?.constellations,
            active: character.constellation,
            tint: character.elementColor
        )
    }

    private func subsectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct CharacterSkillStrip: View {
    let skills: [CharacterSkill]

    var body: some View {
        if !skills.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(skills) { skill in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            CachedAsyncImage(url: skill.icon) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.tint)
                            }
                            .frame(width: 36, height: 36)
                            Spacer(minLength: 10)
                            Text("\(skill.level ?? 0)")
                                .font(.title3.weight(.bold).monospacedDigit())
                        }
                        Text(skill.name ?? "技能")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                    .background(.primary.opacity(0.055), in: .rect(cornerRadius: 8))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(skill.name ?? "技能")，等级 \(skill.level ?? 0)")
                }
            }
        }
    }
}

struct CharacterConstellationStrip: View {
    let values: [CharacterConstellation]?
    let active: Int
    let tint: Color

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(0..<6, id: \.self) { index in
                CharacterConstellationItem(
                    constellation: constellation(at: index),
                    index: index,
                    isActive: index < active,
                    tint: tint
                )
            }
        }
    }

    private func constellation(at index: Int) -> CharacterConstellation? {
        guard let values, index < values.count else { return nil }
        return values[index]
    }
}

private struct CharacterConstellationItem: View {
    let constellation: CharacterConstellation?
    let index: Int
    let isActive: Bool
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(isActive ? tint.opacity(0.18) : Color.primary.opacity(0.06))
            CachedAsyncImage(url: constellation?.icon) {
                Image(systemName: isActive ? "moon.stars.fill" : "lock.fill")
                    .foregroundStyle(isActive ? tint : Color.secondary.opacity(0.5))
            }
            .padding(8)
        }
        .frame(width: 44, height: 44)
        .overlay(borderColor, in: .circle.stroke())
        .help(constellation?.description ?? constellation?.name ?? "\(index + 1) 命")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(constellation?.name ?? "第 \(index + 1) 命座")
        .accessibilityValue(isActive ? "已激活" : "未激活")
    }

    private var borderColor: Color {
        isActive ? tint.opacity(0.34) : Color.secondary.opacity(0.12)
    }
}
