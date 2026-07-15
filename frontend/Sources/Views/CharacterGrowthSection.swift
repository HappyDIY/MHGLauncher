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
