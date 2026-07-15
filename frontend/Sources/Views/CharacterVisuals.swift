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

    var elementSymbol: String {
        switch element.lowercased() {
        case "fire", "pyro": "flame.fill"
        case "water", "hydro": "drop.fill"
        case "wind", "anemo": "wind"
        case "electric", "electro": "bolt.fill"
        case "grass", "dendro": "leaf.fill"
        case "ice", "cryo": "snowflake"
        case "rock", "geo": "mountain.2.fill"
        default: "sparkles"
        }
    }

    var rarityColor: Color {
        rarity >= 5 ? .orange : .purple
    }
}
