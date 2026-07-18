import AppKit
import UniformTypeIdentifiers

struct AchievementPresentation {
    let entries: [AchievementEntry]
    let goals: [AchievementGoal]
    let stats: [Int: (finished: Int, total: Int)]
    let finishDescription: String
}

enum AchievementGoalSelection {
    static func restore(uid: String, goals: [AchievementGoal], defaults: UserDefaults = .standard) -> Int? {
        let ordered = goals.sorted { $0.order < $1.order }
        let saved = defaults.integer(forKey: key(uid))
        return ordered.first(where: { $0.id == saved })?.id ?? ordered.first?.id
    }

    static func save(_ id: Int, uid: String, defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: key(uid))
    }

    static func key(_ uid: String) -> String { "achievementSelectedGoal.\(uid)" }
}

extension AchievementsView {
    var achievementAnimationID: String {
        let archive = store.selectedAchievementArchive?.id ?? ""
        return "\(archive):\(store.value.achievementRevision):\(store.value.achievementEntries.count)"
    }

    func headerSubtitle(_ presentation: AchievementPresentation) -> String {
        "\(store.selectedAchievementArchive?.name ?? "未选择档案") · \(presentation.finishDescription)"
    }

    var achievementPresentation: AchievementPresentation {
        var entries = store.value.achievementEntries.filter(matchesFilters)
        if uncompletedFirst {
            entries.sort {
                let lhsChecked = isChecked($0)
                let rhsChecked = isChecked($1)
                if lhsChecked != rhsChecked { return !lhsChecked }
                if lhsChecked, $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
                return $0.order < $1.order
            }
        } else {
            entries.sort { $0.order < $1.order }
        }
        let goals = store.value.achievementGoals
            .sorted { $0.order < $1.order }
        let stats = store.value.achievementEntries.reduce(into: [Int: (Int, Int)]()) { result, entry in
            var value = result[entry.goal] ?? (0, 0)
            value.1 += 1
            if isChecked(entry) { value.0 += 1 }
            result[entry.goal] = value
        }
        let total = store.value.achievementEntries.count
        let finished = stats.values.reduce(0) { $0 + $1.0 }
        let percent = total == 0 ? 0 : Double(finished) / Double(total)
        let description = "\(finished)/\(total) - \(percent.formatted(.percent.precision(.fractionLength(2))))"
        return AchievementPresentation(
            entries: entries,
            goals: goals,
            stats: stats,
            finishDescription: description
        )
    }

    func isChecked(_ entry: AchievementEntry) -> Bool {
        entry.status >= 2
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.importUIAF(from: url) }
        }
    }

    func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(store.selectedAchievementArchive?.name ?? "achievement").json"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.exportAchievementUIAF(to: url) }
        }
    }

    private func matchesFilters(_ entry: AchievementEntry) -> Bool {
        guard !dailyOnly || entry.isDailyQuest else { return false }
        guard selectedGoal == nil || entry.goal == selectedGoal else { return false }
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        if let id = Int(text) { return entry.achievementId == id }
        if text.range(of: #"^\d\.\d"#, options: .regularExpression) != nil {
            return entry.version.localizedCaseInsensitiveContains(text)
        }
        return entry.title.localizedCaseInsensitiveContains(text)
            || entry.description.localizedCaseInsensitiveContains(text)
    }
}
