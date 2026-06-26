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
        // 固定方形插图区，参考源项目 ItemIcon 的方形等比显示。
        // 角色祈愿立绘（UI_Gacha_AvatarIcon_*）与武器图标（UI_Gacha_EquipIcon_*）
        // 均为带透明背景的完整方形图，统一用 .fit 等比显示，不裁切。
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CachedAsyncImage(
                    url: item.iconUrl,
                    contentMode: .fit
                ) {
                    Image(systemName: mode == .character ? "person.fill" : "sparkles")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(qualityBackground)
            .clipShape(.rect(cornerRadius: 12))
    }

    // 模拟源项目品质背景底色：五星偏金橙、四星偏紫，自上而下渐变。
    private var qualityBackground: some View {
        LinearGradient(
            colors: [accent.opacity(0.55), accent.opacity(0.25)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var amountText: String {
        mode == .character ? "\(item.constellation) 命" : "×\(item.count)"
    }

    private var accent: Color {
        item.rank == 5 ? .orange : .purple
    }
}
