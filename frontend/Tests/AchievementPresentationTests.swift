import Foundation
import Testing
@testable import MHGLauncher

@Suite("成就展示数据")
@MainActor
struct AchievementPresentationTests {
    @Test("一次构建筛选结果与目标统计")
    func buildsFilteredEntriesAndGoalStats() {
        let store = LauncherStore()
        store.value.achievementGoals = [
            AchievementGoal(id: 1, order: 1, name: "天地万象", rewardCount: 10, iconUrl: nil),
            AchievementGoal(id: 2, order: 2, name: "每日委托", rewardCount: 5, iconUrl: nil)
        ]
        store.value.achievementEntries = [
            entry(id: 1, goal: 1, status: 3, daily: false),
            entry(id: 2, goal: 1, status: 0, daily: false),
            entry(id: 3, goal: 2, status: 0, daily: true)
        ]
        let view = AchievementsView(store: store)
        let presentation = view.achievementPresentation

        #expect(presentation.entries.map(\.achievementId) == [2, 3, 1])
        #expect(presentation.goals.map(\.id) == [1, 2])
        #expect(presentation.stats[1]?.finished == 1)
        #expect(presentation.stats[1]?.total == 2)
        #expect(presentation.finishDescription == "1/3 - 33.33%")
    }

    @Test("选择目标后保留其他目标")
    func keepsAllGoalsAfterSelection() {
        let store = LauncherStore()
        store.value.achievementGoals = [
            AchievementGoal(id: 1, order: 1, name: "天地万象", rewardCount: 10, iconUrl: nil),
            AchievementGoal(id: 2, order: 2, name: "每日委托", rewardCount: 5, iconUrl: nil)
        ]
        store.value.achievementEntries = [
            entry(id: 1, goal: 1, status: 0, daily: false),
            entry(id: 2, goal: 2, status: 0, daily: true)
        ]
        let view = AchievementsView(store: store, selectedGoal: 1)

        #expect(view.achievementPresentation.entries.map(\.goal) == [1])
        #expect(view.achievementPresentation.goals.map(\.id) == [1, 2])
    }

    @Test("首次选择第一项并恢复 UID 上次位置")
    func restoresGoalSelectionForUid() {
        let store = LauncherStore()
        store.roles = [InteractiveFixtures.role]
        store.value.achievementGoals = [
            AchievementGoal(id: 1, order: 1, name: "第一项", rewardCount: 5, iconUrl: nil),
            AchievementGoal(id: 2, order: 2, name: "第二项", rewardCount: 5, iconUrl: nil)
        ]
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        #expect(AchievementGoalSelection.restore(
            uid: InteractiveFixtures.role.uid, goals: store.value.achievementGoals, defaults: defaults
        ) == 1)
        AchievementGoalSelection.save(2, uid: InteractiveFixtures.role.uid, defaults: defaults)
        #expect(AchievementGoalSelection.restore(
            uid: InteractiveFixtures.role.uid, goals: store.value.achievementGoals, defaults: defaults
        ) == 2)
    }

    private func entry(id: Int, goal: Int, status: Int, daily: Bool) -> AchievementEntry {
        AchievementEntry(
            archiveId: "archive", achievementId: id, current: status > 0 ? 1 : 0,
            status: status, timestamp: status > 0 ? 1 : 0, updatedAt: "",
            goal: goal, order: id, title: "成就 \(id)", description: "",
            progress: 1, version: "1.0", rewardCount: 5, iconUrl: nil,
            isDailyQuest: daily
        )
    }
}
