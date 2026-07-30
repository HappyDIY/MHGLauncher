import AppKit
import UniformTypeIdentifiers

struct AchievementPresentation {
    let entries: [AchievementEntry]
    let goals: [AchievementGoal]
    let stats: [Int: (finished: Int, total: Int)]
    let finishDescription: String
}

private struct AchievementFilter {
    let text: String
    let achievementID: Int?
    let searchesVersion: Bool
    let selectedGoal: Int?
    let dailyOnly: Bool

    init(text: String, selectedGoal: Int?, dailyOnly: Bool) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = normalized
        achievementID = Int(normalized)
        searchesVersion = Self.isVersionQuery(normalized)
        self.selectedGoal = selectedGoal
        self.dailyOnly = dailyOnly
    }

    func matches(_ entry: AchievementEntry) -> Bool {
        guard !dailyOnly || entry.isDailyQuest else { return false }
        guard selectedGoal == nil || entry.goal == selectedGoal else { return false }
        guard !text.isEmpty else { return true }
        if let achievementID { return entry.achievementId == achievementID }
        if searchesVersion {
            return entry.version.localizedCaseInsensitiveContains(text)
        }
        return entry.title.localizedCaseInsensitiveContains(text)
            || entry.description.localizedCaseInsensitiveContains(text)
    }

    private static func isVersionQuery(_ text: String) -> Bool {
        guard text.count >= 3 else { return false }
        let prefix = text.prefix(3)
        return prefix.first?.wholeNumberValue != nil
            && prefix.dropFirst().first == "."
            && prefix.last?.wholeNumberValue != nil
    }
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
        let allEntries = store.value.achievementEntries
        let filter = AchievementFilter(
            text: searchText,
            selectedGoal: selectedGoal,
            dailyOnly: dailyOnly
        )
        var entries: [AchievementEntry] = []
        entries.reserveCapacity(allEntries.count)
        var stats: [Int: (finished: Int, total: Int)] = [:]
        for entry in allEntries {
            var value = stats[entry.goal] ?? (0, 0)
            value.total += 1
            if isChecked(entry) { value.finished += 1 }
            stats[entry.goal] = value
            if filter.matches(entry) { entries.append(entry) }
        }
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
        let total = allEntries.count
        let finished = stats.values.reduce(0) { $0 + $1.finished }
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

}
