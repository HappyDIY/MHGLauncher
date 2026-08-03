import Foundation

extension LauncherStore {
    func loadAchievementData(
        client: LauncherClient? = nil,
        uid: String? = nil,
        generation: Int? = nil
    ) async throws {
        let api = try client ?? requireClient()
        value.achievementIntent += 1
        let intent = value.achievementIntent
        guard let archiveUid = uid ?? selectedRole?.uid else { return }
        let archive = try await api.achievements.archive(archiveUid)
        guard isCurrentAchievementLoad(intent, uid: uid, generation: generation) else { return }
        let snapshot = try await api.achievements.snapshot(archive.id)
        guard isCurrentAchievementLoad(intent, uid: uid, generation: generation), snapshot.archive.id == archive.id else { return }
        applyAchievementSnapshot(snapshot, archives: [archive])
    }

    func saveAchievement(_ entry: AchievementEntry, checked: Bool) async {
        guard let archiveId = selectedAchievementArchive?.id else { return }
        await perform {
            try await saveAchievement(
                id: entry.achievementId,
                checked: checked,
                archiveId: archiveId,
                retryingConflict: true
            )
        }
    }

    func importUIAF(from url: URL) async {
        guard let archiveId = selectedAchievementArchive?.id else { return }
        let revision = value.achievementRevision
        await perform {
            let snapshot = try await requireClient().achievements.importUIAF(
                try UIGFFileIO.read(from: url), archiveId, revision
            )
            guard selectedAchievementArchive?.id == archiveId,
                  value.achievementRevision == revision else { return }
            applyAchievementSnapshot(snapshot, archives: value.achievementArchives)
        }
    }

    func exportAchievementUIAF(to url: URL) async {
        guard let archiveId = selectedAchievementArchive?.id else { return }
        await perform {
            let data = try await requireClient().achievements.exportUIAF(archiveId)
            try UIGFFileIO.write(data, to: url)
        }
    }

    func uploadCloudAchievements() async {
        guard let uid = selectedRole?.uid else { return }
        await perform {
            let count = try await requireClient().cloud.uploadAchievements(uid)
            value.cloudMessage = "已上传 \(count) 条成就"
        }
    }

    func retrieveCloudAchievements() async {
        guard let uid = selectedRole?.uid else { return }
        await perform {
            let count = try await requireClient().cloud.retrieveAchievements(uid)
            try await loadAchievementData(uid: uid)
            value.cloudMessage = "已取回 \(count) 条成就"
        }
    }

    var selectedAchievementArchive: AchievementArchive? {
        value.achievementArchives.first(where: \.selected) ?? value.achievementArchives.first
    }

    private func applyAchievementSnapshot(
        _ snapshot: AchievementSnapshot,
        archives: [AchievementArchive]
    ) {
        value.achievementArchives = archives.map {
            $0.id == snapshot.archive.id ? snapshot.archive : $0
        }
        value.achievementEntries = snapshot.entries
        value.achievementRevision = snapshot.revision
    }

    private func isCurrentAchievementLoad(_ intent: Int, uid: String?, generation: Int?) -> Bool {
        guard intent == value.achievementIntent else { return false }
        guard let uid, let generation else { return true }
        return isCurrentCompanionData(uid: uid, generation: generation)
    }

    private func saveAchievement(
        id: Int,
        checked: Bool,
        archiveId: String,
        retryingConflict: Bool
    ) async throws {
        guard selectedAchievementArchive?.id == archiveId,
              let entry = value.achievementEntries.first(where: { $0.achievementId == id }) else { return }
        let revision = value.achievementRevision
        let item = AchievementItemInput(
            achievementId: id,
            current: checked ? entry.progress : entry.current,
            status: checked ? 3 : 0,
            timestamp: checked ? Int(Date().timeIntervalSince1970) : 0
        )
        do {
            let snapshot = try await requireClient().achievements.save(
                AchievementSaveRequest(
                    archiveId: archiveId, expectedRevision: revision, items: [item]
                )
            )
            guard selectedAchievementArchive?.id == archiveId,
                  value.achievementRevision == revision else { return }
            applyAchievementSnapshot(snapshot, archives: value.achievementArchives)
        } catch let error as LauncherCoreError where error.code == "archive_revision_conflict" {
            guard retryingConflict else { throw error }
            try await loadAchievementData()
            try await saveAchievement(id: id, checked: checked, archiveId: archiveId, retryingConflict: false)
        }
    }
}
