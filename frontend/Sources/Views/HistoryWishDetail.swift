import SwiftUI

struct HistoryWishDetail: View {
    let wish: HistoryWishEvent
    let category: HistoryWishCategory
    @State private var bannerID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if bannerPaging.count > 1 {
                    HistoryWishBannerNavigation(
                        paging: bannerPaging,
                        previous: { moveBanner(by: -1) },
                        next: { moveBanner(by: 1) }
                    )
                }
                HistoryWishBannerCarousel(
                    wish: wish,
                    banners: visibleBanners,
                    selectedID: $bannerID
                )
                statisticsHeader
                itemSection("五星 UP", icon: "star.fill", items: wish.orangeUp, color: .orange)
                itemSection("四星 UP", icon: "star.leadinghalf.filled", items: wish.purpleUp, color: .purple)
                itemSection("五星结果", icon: "sparkles", items: wish.summary, color: .orange)
                itemSection("四星结果", icon: "diamond.fill", items: wish.purple, color: .purple)
                itemSection("三星结果", icon: "circle.fill", items: wish.blue, color: .blue)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(
            .regular.tint(wish.poolTint.opacity(0.06)),
            in: .rect(cornerRadius: 22)
        )
        .motionAnimation(.selection, value: wish.id)
        .onAppear { resetBanner() }
        .onChange(of: wish.id) { resetBanner() }
    }

    private var bannerPaging: HistoryWishBannerPaging {
        HistoryWishBannerPaging(
            ids: visibleBanners.map(\.id),
            selectedID: bannerID ?? wish.id
        )
    }

    private var visibleBanners: [HistoryWishBanner] {
        category.banners(in: wish.banners)
    }

    private func moveBanner(by offset: Int) {
        guard let id = bannerPaging.adjacentID(offset: offset) else { return }
        withAnimation(LauncherMotion.animation(.selection, reduceMotion: reduceMotion)) {
            bannerID = id
        }
    }

    private func resetBanner() {
        bannerID = visibleBanners.contains { $0.id == wish.id }
            ? wish.id
            : visibleBanners.first?.id
    }

    private var statisticsHeader: some View {
        HStack {
            Label("抽取统计 · \(wish.name)", systemImage: "chart.bar.xaxis")
                .font(.headline)
            Spacer()
            Text(wish.totalText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
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
