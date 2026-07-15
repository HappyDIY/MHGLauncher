import SwiftUI

struct CharacterIcon: View {
    let character: GameCharacter
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(character.elementColor.opacity(0.11))
            CachedAsyncImage(url: character.iconUrl) {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(character.elementColor)
            }
            .padding(size * 0.045)
            rarityBadge
                .padding(5)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: min(size * 0.1, 12)))
        .overlay(
            character.elementColor.opacity(0.28),
            in: .rect(cornerRadius: min(size * 0.1, 12)).stroke()
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.name)，\(character.rarity) 星")
    }

    private var rarityBadge: some View {
        Label("\(character.rarity)", systemImage: "star.fill")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.62), in: .capsule)
    }
}
