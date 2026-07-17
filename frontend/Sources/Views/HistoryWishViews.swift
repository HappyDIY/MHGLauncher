import SwiftUI

struct HistoryWishRow: View {
    let wish: HistoryWishEvent
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(wish.poolTitle, systemImage: wish.poolIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(wish.poolTint)
                    Spacer()
                    Text(wish.totalText)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(wish.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("版本 \(wish.version.nonempty ?? "未知")")
                    Text("·")
                    Text(wish.timeSpan)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(wish.poolTint)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "已选择" : "未选择")
        .motionHover(selected ? .selection : .subtle)
        .glassEffect(
            selected
                ? .regular.tint(wish.poolTint.opacity(0.18)).interactive()
                : .clear.interactive(),
            in: .rect(cornerRadius: 14)
        )
        .motionAnimation(.selection, value: selected)
    }
}

struct HistoryWishIcon: View {
    let item: HistoryWishItem
    let size: CGFloat
    let showsBadge: Bool

    var body: some View {
        CachedAsyncImage(url: item.iconUrl, maxPixelDimension: 128) {
            Image(systemName: item.itemType == "角色" ? "person.fill" : "sparkles")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
        }
        .frame(width: size, height: size)
        .background(rarityGradient(item.rank))
        .clipShape(.rect(cornerRadius: 8))
        .opacity(item.count > 0 ? 1 : 0.42)
        .overlay(alignment: .topTrailing) {
            if showsBadge { badge(item.count) }
        }
        .help("\(item.name) × \(item.count)")
        .accessibilityLabel("\(item.name)，数量 \(item.count)")
    }

    private func badge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.black.opacity(0.55), in: .rect(cornerRadius: 5))
    }

    private func rarityGradient(_ rank: Int) -> LinearGradient {
        let colors: [Color] = switch rank {
        case 5: [.orange.opacity(0.86), .purple.opacity(0.58)]
        case 4: [.purple.opacity(0.82), .indigo.opacity(0.58)]
        default: [.blue.opacity(0.66), .gray.opacity(0.46)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension HistoryWishEvent {
    var poolTitle: String { gachaType.gachaPoolTitle }
    var poolIcon: String { gachaType.gachaPoolIcon }
    var poolTint: Color { gachaType.gachaPoolTint }
}

extension HistoryWishBanner {
    var poolTitle: String { gachaType.gachaPoolTitle }
    var poolIcon: String { gachaType.gachaPoolIcon }
    var poolTint: Color { gachaType.gachaPoolTint }
}

private extension String {
    var gachaPoolTitle: String {
        switch self {
        case "301": "角色活动"
        case "400": "角色活动 · 2"
        case "302": "武器活动"
        case "500": "集录祈愿"
        default: "活动祈愿"
        }
    }

    var gachaPoolIcon: String {
        switch self {
        case "302": "shield.lefthalf.filled"
        case "500": "sparkles.rectangle.stack.fill"
        default: "person.2.fill"
        }
    }

    var gachaPoolTint: Color {
        switch self {
        case "302": .orange
        case "500": .purple
        case "400": .indigo
        default: .cyan
        }
    }
}
