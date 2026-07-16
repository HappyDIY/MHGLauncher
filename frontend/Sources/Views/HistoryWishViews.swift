import SwiftUI

struct HistoryWishRow: View {
    let wish: HistoryWishEvent
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("版本 \(wish.version.nonempty ?? "未知")  \(wish.name)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(wish.totalText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    upStrip(wish.orangeUp, maxWidth: 134)
                    Spacer(minLength: 10)
                    upStrip(wish.purpleUp, maxWidth: 272)
                }
                Text(wish.timeSpan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "已选择" : "未选择")
        .motionHover(.subtle)
    }

    private func upStrip(_ items: [HistoryWishItem], maxWidth: CGFloat) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44, maximum: 48), spacing: 4)],
            spacing: 4
        ) {
            ForEach(items) { item in
                VStack(spacing: 3) {
                    HistoryWishIcon(item: item, size: 40, showsBadge: false)
                    Text("\(item.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.16) : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(selected ? 0.12 : 0.06))
            }
    }
}

struct HistoryWishDetail: View {
    let wish: HistoryWishEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                banner
                itemSection("五星", items: wish.summary, color: .orange)
                itemSection("四星", items: wish.purple, color: .purple)
                itemSection("三星", items: wish.blue, color: .blue)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .motionAnimation(.selection, value: wish.id)
    }

    private var banner: some View {
        ZStack {
            CachedAsyncImage(
                url: wish.bannerUrl,
                contentMode: .fill,
                maxPixelDimension: 1536
            ) {
                LinearGradient(
                    colors: [.cyan.opacity(0.35), .purple.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: icon(for: wish.gachaType))
                        .font(.system(size: 46))
                        .foregroundStyle(.white.opacity(0.75))
                )
            }
            .aspectRatio(1080 / 533, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12))
            Color.black.opacity(0.10).clipShape(.rect(cornerRadius: 12))
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }

    private func itemSection(
        _ title: String,
        items: [HistoryWishItem],
        color: Color
    ) -> some View {
        Group {
            if !items.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 54, maximum: 64), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(items) { HistoryWishIcon(item: $0, size: 54, showsBadge: true) }
                }
            }
        }
    }

    private func icon(for type: String) -> String {
        type.normalizedGachaType == "302" ? "shield.lefthalf.filled" : "sparkles"
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
            if showsBadge || item.count > 0 { badge(item.count) }
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
