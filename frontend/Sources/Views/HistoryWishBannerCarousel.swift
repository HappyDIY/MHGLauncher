import SwiftUI

struct HistoryWishBannerCarousel: View {
    let wish: HistoryWishEvent
    @Binding var selectedID: String?

    private var banners: [HistoryWishBanner] {
        if !wish.banners.isEmpty { return wish.banners }
        return [HistoryWishBanner(
            id: wish.id,
            name: wish.name,
            gachaType: wish.gachaType,
            bannerUrl: wish.bannerUrl
        )]
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(banners) { banner in
                    bannerCard(banner)
                        .containerRelativeFrame(.horizontal)
                        .id(banner.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selectedID)
        .aspectRatio(1080 / 533, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.16))
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .accessibilityLabel("同期祈愿横幅，可左右滑动翻页")
    }

    private func bannerCard(_ banner: HistoryWishBanner) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(
                url: banner.bannerUrl,
                contentMode: .fill,
                maxPixelDimension: 1536
            ) {
                LinearGradient(
                    colors: [banner.poolTint.opacity(0.52), .purple.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: banner.poolIcon)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )
            bannerLabel(banner)
        }
    }

    private func bannerLabel(_ banner: HistoryWishBanner) -> some View {
        let showsStatistics = banner.gachaType.normalizedGachaType == wish.gachaType
        return VStack(alignment: .leading, spacing: 5) {
            Text("\(wish.phaseTitle) · \(banner.poolTitle)")
                .font(.caption.weight(.semibold))
            Text(banner.name)
                .font(.title2.bold())
            HStack(spacing: 12) {
                Label(wish.timeSpan, systemImage: "calendar")
                Label(
                    showsStatistics ? wish.totalText : "同期横幅",
                    systemImage: showsStatistics ? "sparkles" : "rectangle.stack"
                )
            }
            .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}
