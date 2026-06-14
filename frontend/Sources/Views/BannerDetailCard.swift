import SwiftUI

struct BannerDetailCard: View {
    let detail: WishBannerDetail
    let isExpanded: Bool

    private var poolName: String {
        switch detail.gachaType {
        case "100": "新手祈愿"
        case "200": "常驻祈愿"
        case "301": "角色活动祈愿"
        case "302": "武器活动祈愿"
        default: "卡池 \(detail.gachaType)"
        }
    }

    private var pityProgress: Double {
        guard detail.guaranteeThreshold > 0 else { return 0 }
        return min(Double(detail.lastPity) / Double(detail.guaranteeThreshold), 1)
    }

    private var pityBarColor: Color {
        if detail.lastPity >= detail.guaranteeThreshold - 10 { .orange }
        else if detail.lastPity >= detail.guaranteeThreshold / 2 { .yellow }
        else { .green }
    }

    var body: some View {
        GlassCard(poolName, icon: "sparkles") {
            VStack(alignment: .leading, spacing: 14) {
                pitySection
                Divider()
                statGrid
                if isExpanded {
                    Divider()
                    itemsList
                }
            }
        }
    }

    private var pitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("保底进度")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(detail.lastPity) / \(detail.guaranteeThreshold)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(pityBarColor)
                        .frame(width: geometry.size.width * pityProgress, height: 8)
                }
            }
            .frame(height: 8)
            HStack(spacing: 20) {
                pityMetric(label: "距上次五星", value: "\(detail.lastPity)")
                pityMetric(label: "距上次四星", value: "\(detail.lastPurplePity)")
                pityMetric(label: "保底余量", value: "\(max(0, detail.guaranteeThreshold - detail.lastPity))")
                Spacer()
            }
        }
    }

    private func pityMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                MetricView(value: "\(detail.total)", label: "总抽数")
                MetricView(value: "\(detail.fiveStarCount)", label: "五星")
                MetricView(value: "\(detail.fourStarCount)", label: "四星")
                MetricView(value: "\(detail.threeStarCount)", label: "三星")
            }
            HStack(spacing: 24) {
                MetricView(
                    value: String(format: "%.1f%%", detail.fiveStarPercent * 100),
                    label: "五星率"
                )
                MetricView(
                    value: detail.averagePity > 0
                        ? String(format: "%.1f", detail.averagePity) : "--",
                    label: "平均保底"
                )
                MetricView(value: "\(detail.maxPity)", label: "最非记录")
                if detail.minPity > 0 {
                    MetricView(value: "\(detail.minPity)", label: "最欧记录")
                }
            }
        }
    }

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("五星产出记录")
                .font(.subheadline.weight(.medium))
            if detail.fiveStarItems.isEmpty {
                Text("暂无五星记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.fiveStarItems) { item in
                    HStack(spacing: 8) {
                        CachedAsyncImage(url: item.iconUrl) {
                            Image(systemName: item.itemType == "角色" ? "person.fill" : "sparkles")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(width: 28, height: 28)
                        .background(item.rank == 5 ? Color.orange.opacity(0.3) : Color.purple.opacity(0.3))
                        .clipShape(.rect(cornerRadius: 6))
                        Text(item.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text("第 \(item.pullNumber) 抽")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(item.time.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
