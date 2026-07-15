import SwiftUI

struct CharacterGrowthSection: View {
    let character: GameCharacter

    @ViewBuilder
    var body: some View {
        if !combatSkills.isEmpty {
            SectionPanel(title: "天赋", icon: "sparkles") {
                CharacterSkillStrip(skills: combatSkills)
            }
        }
    }

    private var combatSkills: [CharacterSkill] {
        let skills = character.payload?.skills ?? []
        if skills.contains(where: { $0.skillType != nil }) {
            return skills.filter(\.isCombatTalent)
        }
        return Array(skills.prefix(3))
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
                            ZStack {
                                Circle()
                                    .fill(Color.secondary.opacity(0.2))
                                CachedAsyncImage(url: skill.icon) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(.circle)
                            .overlay(Color.secondary.opacity(0.16), in: .circle.stroke())
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
