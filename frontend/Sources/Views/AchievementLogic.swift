import AppKit
import UniformTypeIdentifiers

extension AchievementsView {
    var filteredEntries: [AchievementEntry] {
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
        return entries
    }

    var visibleGoals: [AchievementGoal] {
        let included = Set(filteredEntries.map(\.goal))
        return store.value.achievementGoals
            .filter { included.contains($0.id) || selectedGoal == $0.id }
            .sorted { $0.order < $1.order }
    }

    var goalStats: [Int: (Int, Int)] {
        store.value.achievementEntries.reduce(into: [:]) { result, entry in
            var value = result[entry.goal] ?? (0, 0)
            value.1 += 1
            if isChecked(entry) { value.0 += 1 }
            result[entry.goal] = value
        }
    }

    var finishDescription: String {
        let total = store.value.achievementEntries.count
        let finished = store.value.achievementEntries.filter(isChecked).count
        let percent = total == 0 ? 0 : Double(finished) / Double(total)
        return "\(finished)/\(total) - \(percent.formatted(.percent.precision(.fractionLength(2))))"
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
