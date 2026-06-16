import SwiftUI

struct BannerDetailCard: View {
    let details: [WishBannerDetail]
    @Binding var selection: String?

    private var selectedDetail: WishBannerDetail? {
        details.first { $0.id == selection }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PoolSelector(details: details, selection: $selection)
                if let detail = selectedDetail {
                    detailContent(detail)
                } else {
                    emptySelection
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(
            .regular.tint(selectedDetail?.poolAccent.opacity(0.08) ?? Color.accentColor.opacity(0.08)),
            in: .rect(cornerRadius: 22)
        )
    }

    private func detailContent(_ detail: WishBannerDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heading(detail)
            pitySection(detail)
            Divider()
            metrics(detail)
            Divider()
            WishFiveStarTimeline(
                items: detail.fiveStarItems,
                maximum: detail.guaranteeThreshold
            )
        }
    }

    private var emptySelection: some View {
        ContentUnavailableView(
            "选择卡池",
            systemImage: "rectangle.stack",
            description: Text("在上方选择卡池后，这里会展示详细统计数据。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heading(_ detail: WishBannerDetail) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.poolName)
                    .font(.title3.bold())
                Text("\(detail.total) 抽 · \(detail.fiveStarCount) 个五星")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: detail.poolIcon)
                .font(.title2)
                .foregroundStyle(detail.poolAccent)
                .frame(width: 42, height: 42)
                .glassEffect(
                    .regular.tint(detail.poolAccent.opacity(0.18)),
                    in: .circle
                )
        }
    }

    private func pitySection(_ detail: WishBannerDetail) -> some View {
        VStack(spacing: 13) {
            PityProgressRow(
                title: "五星保底",
                value: detail.lastPity,
                maximum: detail.guaranteeThreshold,
                color: .orange
            )
            PityProgressRow(
                title: "四星保底",
                value: detail.lastPurplePity,
                maximum: 10,
                color: .purple
            )
        }
    }

    private func metrics(_ detail: WishBannerDetail) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            metricCard("\(detail.fiveStarCount)", "五星", .orange)
            metricCard("\(detail.fourStarCount)", "四星", .purple)
            metricCard(String(format: "%.1f%%", detail.fiveStarPercent * 100), "五星率", .cyan)
            metricCard(
                detail.averagePity > 0 ? String(format: "%.1f", detail.averagePity) : "--", "平均出金",
                .yellow
            )
            metricCard(detail.maxPity > 0 ? "\(detail.maxPity)" : "--", "最晚出金", .red)
            metricCard(detail.minPity > 0 ? "\(detail.minPity)" : "--", "最快出金", .green)
        }
    }

    private func metricCard(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(height: 3)
                .padding(.horizontal, 4)
        }
    }

}

private struct PityProgressRow: View {
    let title: String
    let value: Int
    let maximum: Int
    let color: Color

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(value) / \(maximum)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(color)
            }
            ProgressView(value: min(Double(value) / Double(max(maximum, 1)), 1))
                .tint(color)
        }
    }
}
