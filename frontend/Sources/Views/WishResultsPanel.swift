import SwiftUI

struct WishResultsPanel: View {
    let records: [WishRecord]
    @State private var mode = WishResultMode.character

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            WishResultCard(item: item, mode: mode)
                                .id("\(mode.rawValue)-\(item.id)")
                                .motionScrollAppearance()
                                .motionEntrance(order: index)
                        }
                    }
                    .padding(2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .motionAnimation(.selection, value: mode)
    }

    private var heading: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("抽卡成果")
                    .font(.headline)
                Text("\(items.count) 种\(mode.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("成果类型", selection: $mode) {
                ForEach(WishResultMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
            .motionHover(.subtle)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "暂无\(mode.title)成果",
            systemImage: mode == .character ? "person.crop.square" : "sparkles",
            description: Text("同步或导入包含四星、五星\(mode.title)的祈愿记录后将在此展示。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var items: [WishResultItem] {
        records.resultItems(for: mode)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 12)]
    }
}

private struct WishResultCard: View {
    let item: WishResultItem
    let mode: WishResultMode

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            artwork
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack {
                Text(String(repeating: "★", count: item.rank))
                    .foregroundStyle(item.rank == 5 ? .orange : .purple)
                Spacer()
                Text(amountText)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(10)
        .glassEffect(
            .clear.tint(accent.opacity(0.1)).interactive(),
            in: .rect(cornerRadius: 16)
        )
        .motionAnimation(.content, value: amountText)
    }

    private var artwork: some View {
        CachedAsyncImage(
            url: item.iconUrl,
            contentMode: mode == .character ? .fill : .fit
        ) {
            Image(systemName: mode == .character ? "person.fill" : "sparkles")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.8), .indigo.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(.rect(cornerRadius: 12))
    }

    private var amountText: String {
        mode == .character ? "\(item.constellation) 命" : "×\(item.count)"
    }

    private var accent: Color {
        item.rank == 5 ? .orange : .purple
    }
}
