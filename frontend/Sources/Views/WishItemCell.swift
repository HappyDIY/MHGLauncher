import SwiftUI

struct WishItemCell: View {
    let item: WishRecord

    var body: some View {
        HStack(spacing: 10) {
            artwork
            Text(item.name)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private var artwork: some View {
        AsyncImage(url: item.iconUrl) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
            case .empty:
                ProgressView()
                    .controlSize(.small)
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: 38, height: 38)
        .background(rarityGradient)
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: item.itemType == "角色" ? "person.fill" : "sparkles")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
    }

    private var rarityGradient: LinearGradient {
        let colors: [Color] = switch item.rank {
        case 5: [.orange.opacity(0.82), .purple.opacity(0.58)]
        case 4: [.purple.opacity(0.78), .indigo.opacity(0.54)]
        default: [.blue.opacity(0.62), .gray.opacity(0.42)]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
