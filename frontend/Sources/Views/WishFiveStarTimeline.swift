import SwiftUI

struct WishFiveStarTimeline: View {
    let items: [WishBannerItem]
    let maximum: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("五星记录")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(items.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                ContentUnavailableView(
                    "暂无五星记录",
                    systemImage: "star",
                    description: Text("继续同步后，五星记录会显示在这里。")
                )
                .controlSize(.small)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        FiveStarPullRow(item: item, maximum: maximum)
                            .motionEntrance(order: index)
                    }
                }
            }
        }
    }
}

private struct FiveStarPullRow: View {
    let item: WishBannerItem
    let maximum: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(.white.opacity(0.035))
                RoundedRectangle(cornerRadius: 11)
                    .fill(progressGradient.opacity(0.2))
                    .frame(width: geometry.size.width * progress)
                content
            }
        }
        .frame(height: 52)
        .motionAnimation(.progress, value: item.pity)
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(.white.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name)，\(item.pity) 抽")
    }

    private var content: some View {
        HStack(spacing: 11) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.time.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(item.pity)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(pullColor)
            Text("抽")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 12)
    }

    private var artwork: some View {
        CachedAsyncImage(url: item.iconUrl, contentMode: .fill) {
            Image(systemName: item.itemType == "角色" ? "person.fill" : "sparkles")
                .foregroundStyle(.white.opacity(0.86))
        }
        .scaleEffect(item.itemType == "角色" ? 1.28 : 1.12)
        .frame(width: 52, height: 52)
        .background(.orange.opacity(0.18))
        .clipped()
        .clipShape(.rect(cornerRadius: 11))
    }

    private var progress: Double {
        min(Double(item.pity) / Double(max(maximum, 1)), 1)
    }

    private var pullColor: Color {
        if progress >= 0.8 { .orange }
        else if progress >= 0.5 { .yellow }
        else { .secondary }
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [pullColor, pullColor.opacity(0.35)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
