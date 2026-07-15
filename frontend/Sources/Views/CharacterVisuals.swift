import SwiftUI

extension GameCharacter {
    var elementColor: Color {
        switch element.lowercased() {
        case "fire", "pyro": .red
        case "water", "hydro": .blue
        case "wind", "anemo": .teal
        case "electric", "electro": .purple
        case "grass", "dendro": .green
        case "ice", "cryo": .cyan
        case "rock", "geo": .yellow
        default: .secondary
        }
    }

    var elementAssetName: String? {
        switch element.lowercased() {
        case "fire", "pyro": "ElementFire"
        case "water", "hydro": "ElementWater"
        case "wind", "anemo": "ElementWind"
        case "electric", "electro": "ElementElectric"
        case "grass", "dendro": "ElementGrass"
        case "ice", "cryo": "ElementIce"
        case "rock", "geo": "ElementRock"
        default: nil
        }
    }

    var rarityColor: Color {
        rarity >= 5 ? .orange : .purple
    }
}

struct CharacterElementIcon: View {
    let character: GameCharacter
    let size: CGFloat

    var body: some View {
        Group {
            if let name = character.elementAssetName {
                Image(name, bundle: CharacterResources.bundle)
                    .resizable()
                    .renderingMode(.template)
            } else {
                Image(systemName: "questionmark.circle")
                    .resizable()
            }
        }
        .scaledToFit()
        .foregroundStyle(character.elementColor)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum CharacterResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(
            forResource: "MHGLauncher_MHGLauncher",
            withExtension: "bundle"
        ), let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
}
