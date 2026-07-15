import SwiftUI

struct CharacterSkillStrip: View {
    let skills: [CharacterSkill]

    var body: some View {
        if !skills.isEmpty {
            HStack(spacing: 8) {
                ForEach(skills) { skill in
                    HStack(spacing: 8) {
                        CachedAsyncImage(url: skill.icon) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.tint)
                        }
                        .frame(width: 28, height: 28)
                        Text("\(skill.level ?? 0)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.primary.opacity(0.07), in: .capsule)
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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { index in
                let constellation = values?.dropFirst(index).first
                ZStack {
                    Circle()
                        .fill(
                            index < active
                                ? Color.accentColor.opacity(0.18)
                                : Color.primary.opacity(0.06)
                        )
                    CachedAsyncImage(url: constellation?.icon) {
                        Image(systemName: index < active ? "moon.stars.fill" : "lock.fill")
                            .foregroundStyle(
                                index < active
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.5)
                            )
                    }
                    .padding(8)
                }
                .frame(width: 38, height: 38)
                .help(constellation?.description ?? constellation?.name ?? "\(index + 1) 命")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(constellation?.name ?? "第 \(index + 1) 命座")
                .accessibilityValue(index < active ? "已激活" : "未激活")
            }
        }
    }
}

struct CharacterPropertySection: View {
    let character: GameCharacter

    var body: some View {
        let values = character.payload?.selectedProperties ?? []
        if !values.isEmpty {
            SectionPanel(title: "角色属性", icon: "chart.bar") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    ForEach(values) { property in
                        HStack {
                            Text(property.name ?? "")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(property.value ?? "")
                                .fontWeight(.semibold)
                            if let add = property.addValue, !add.isEmpty {
                                Text(add)
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.callout)
                        .padding(10)
                        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

struct CharacterRecommendationSection: View {
    let character: GameCharacter

    var body: some View {
        if let value = character.payload?.recommendRelicProperty, !groups(value).isEmpty {
            SectionPanel(title: "推荐词条", icon: "wand.and.stars") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    ForEach(groups(value), id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            FlowTags(values: group.values)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func groups(_ value: CharacterRecommendation) -> [(title: String, values: [String])] {
        [
            ("时之沙", value.sandProperties ?? []),
            ("空之杯", value.gobletProperties ?? []),
            ("理之冠", value.circletProperties ?? []),
            ("副词条", value.subProperties ?? []),
        ].filter { !$0.values.isEmpty }
    }
}

struct CharacterReliquarySection: View {
    let character: GameCharacter

    var body: some View {
        let relics = character.payload?.relics ?? []
        if !relics.isEmpty {
            SectionPanel(title: "圣遗物", icon: "seal") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                    ForEach(relics) { relic in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                CachedAsyncImage(url: relic.icon) {
                                    Image(systemName: "seal.fill")
                                        .foregroundStyle(.orange)
                                }
                                .frame(width: 42, height: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(relic.name ?? "圣遗物")
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(relic.setName ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("+\(relic.level ?? 0)")
                                    .font(.callout.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            CharacterPropertyLine(property: relic.mainProperty, bold: true)
                            ForEach(relic.subProperties ?? []) { property in
                                CharacterPropertyLine(property: property, bold: false)
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 8))
                    }
                }
            }
        }
    }
}
