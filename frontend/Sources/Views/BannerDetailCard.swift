import SwiftUI

struct BannerDetailCard: View {
    let detail: WishBannerDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading
            pitySection
            Divider()
            metrics
            Divider()
            WishFiveStarTimeline(
                items: detail.fiveStarItems,
                maximum: detail.guaranteeThreshold
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(
            .regular.tint(detail.poolAccent.opacity(0.08)),
            in: .rect(cornerRadius: 22)
        )
    }

    private var heading: some View {
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

    private var pitySection: some View {
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

    private var metrics: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
            GridRow {
                compactMetric("\(detail.fiveStarCount)", "五星")
                compactMetric("\(detail.fourStarCount)", "四星")
                compactMetric(String(format: "%.2f%%", detail.fiveStarPercent * 100), "五星率")
            }
            GridRow {
                compactMetric(
                    detail.averagePity > 0 ? String(format: "%.1f", detail.averagePity) : "--",
                    "平均出金"
                )
                compactMetric(detail.maxPity > 0 ? "\(detail.maxPity)" : "--", "最晚出金")
                compactMetric(detail.minPity > 0 ? "\(detail.minPity)" : "--", "最快出金")
            }
        }
    }

    private func compactMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
