import SwiftUI

struct HistoryWishDetail: View {
    let wish: HistoryWishEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                banner
                itemSection("五星 UP", icon: "star.fill", items: wish.orangeUp, color: .orange)
                itemSection("四星 UP", icon: "star.leadinghalf.filled", items: wish.purpleUp, color: .purple)
                itemSection("五星结果", icon: "sparkles", items: wish.summary, color: .orange)
                itemSection("四星结果", icon: "diamond.fill", items: wish.purple, color: .purple)
                itemSection("三星结果", icon: "circle.fill", items: wish.blue, color: .blue)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            Color.clear.glassEffect(
                .regular.tint(wish.poolTint.opacity(0.06)),
                in: .rect(cornerRadius: 22)
            )
        }
        .motionAnimation(.selection, value: wish.id)
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(
                url: wish.bannerUrl,
                contentMode: .fill,
                maxPixelDimension: 1536
            ) {
                LinearGradient(
                    colors: [wish.poolTint.opacity(0.52), .purple.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: wish.poolIcon)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .aspectRatio(1080 / 533, contentMode: .fit)
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )
            bannerLabel
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.16))
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }

    private var bannerLabel: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("版本 \(wish.version.nonempty ?? "未知") · \(wish.poolTitle)")
                .font(.caption.weight(.semibold))
            Text(wish.name)
                .font(.title2.bold())
            HStack(spacing: 12) {
                Label(wish.timeSpan, systemImage: "calendar")
                Label(wish.totalText, systemImage: "sparkles")
            }
            .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    @ViewBuilder
    private func itemSection(
        _ title: String,
        icon: String,
        items: [HistoryWishItem],
        color: Color
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(color)
                    Spacer()
                    Text("\(items.count) 种")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 126, maximum: 190), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(items) { itemTile($0, color: color) }
                }
            }
            .padding(13)
            .background(color.opacity(0.055), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.12))
            }
        }
    }

    private func itemTile(_ item: HistoryWishItem, color: Color) -> some View {
        HStack(spacing: 9) {
            HistoryWishIcon(item: item, size: 44, showsBadge: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(String(repeating: "★", count: item.rank))
                    .font(.caption2)
                    .foregroundStyle(color)
            }
            Spacer(minLength: 2)
            Text(item.count > 0 ? "×\(item.count)" : "未抽到")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.primary.opacity(0.035), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
