import SwiftUI

struct WishOverviewHero: View {
    let records: [WishRecord]
    let details: [WishBannerDetail]
    let uid: String?

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("祈愿概览", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Text(dateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            heroMetric("\(records.count)", "总祈愿", color: .primary)
            heroMetric("\(fiveStarCount)", "五星", color: .orange)
            heroMetric("\(fourStarCount)", "四星", color: .purple)
            heroMetric("\(details.count)", "卡池", color: .cyan)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .glassEffect(.regular.tint(.cyan.opacity(0.05)), in: .rect(cornerRadius: 22))
    }

    private var fiveStarCount: Int {
        records.count { $0.rank == 5 }
    }

    private var fourStarCount: Int {
        records.count { $0.rank == 4 }
    }

    private var dateRange: String {
        guard let oldest = records.last?.time, let newest = records.first?.time else {
            return uid.map { "UID \($0)" } ?? "暂无记录"
        }
        let range = "\(oldest.formatted(date: .abbreviated, time: .omitted)) 至 "
            + newest.formatted(date: .abbreviated, time: .omitted)
        return uid.map { "UID \($0) · \(range)" } ?? range
    }

    private func heroMetric(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .motionAnimation(.content, value: value)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 62, alignment: .trailing)
    }
}
