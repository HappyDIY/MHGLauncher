import AppKit
import SwiftUI

enum AchievementLayoutMode: String, CaseIterable, Identifiable {
    case list = "列表"
    case grid = "网格"
    var id: Self { self }
}

struct AchievementGoalCell: View {
    let goal: AchievementGoal
    let finished: Int
    let total: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.name).lineLimit(2)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .tint(progressTint)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.16) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .motionHover(selected ? .selection : .subtle)
    }

    private var icon: some View {
        CachedAsyncImage(url: goal.iconUrl) {
            Image(systemName: "trophy.fill").foregroundStyle(.secondary)
        }
        .padding(5)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var progress: Double {
        total == 0 ? 0 : Double(finished) / Double(total)
    }

    private var progressText: String {
        "\(finished)/\(total) - \(progress.formatted(.percent.precision(.fractionLength(2))))"
    }

    private var progressTint: Color {
        progress >= 1 ? .green : progress >= 0.5 ? .orange : .accentColor
    }
}

struct AchievementEntryRow: View {
    let entry: AchievementEntry
    let checked: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { checked },
                set: { value in onToggle(value) }
            ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 5) {
                titleLine
                Text(entry.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if checked {
                Text(finishedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Label("\(entry.rewardCount)", systemImage: "diamond.fill")
                .font(.caption)
                .foregroundStyle(.pink)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("复制成就 ID", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(entry.achievementId)", forType: .string)
            }
            Button("在米游社搜索", systemImage: "magnifyingglass") {
                open("https://www.miyoushe.com/ys/search?keyword=\(query)")
            }
            Button("在 HoYoLAB 搜索", systemImage: "globe") {
                open("https://www.hoyolab.com/search?keyword=\(query)")
            }
        }
        .motionHover(.subtle)
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(entry.title).font(.headline).lineLimit(1)
            Text(entry.version)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("#\(entry.achievementId)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var finishedTime: String {
        guard entry.timestamp > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
        return date.formatted(.dateTime.year().month().day().hour().minute())
    }

    private var query: String {
        "原神 \(entry.title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entry.title
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
