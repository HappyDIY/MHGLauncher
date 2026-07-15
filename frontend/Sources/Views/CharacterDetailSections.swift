import SwiftUI

struct CharacterPropertySection: View {
    let character: GameCharacter

    var body: some View {
        let values = character.payload?.selectedProperties ?? []
        if !values.isEmpty {
            SectionPanel(title: "角色属性", icon: "chart.bar") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    ForEach(values) { property in
                        VStack(spacing: 8) {
                            HStack {
                                Text(property.name ?? "")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Spacer()
                                Text(property.value ?? "")
                                    .fontWeight(.semibold)
                                if let add = property.addValue, !add.isEmpty {
                                    Text(add)
                                        .foregroundStyle(.green)
                                }
                            }
                            Divider()
                        }
                        .font(.callout)
                        .padding(.horizontal, 4)
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
                        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 8))
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
                                        .lineLimit(2)
                                    Text(relic.setName ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
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
                        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 8))
                        .overlay(.primary.opacity(0.08), in: .rect(cornerRadius: 8).stroke())
                    }
                }
            }
        }
    }
}
