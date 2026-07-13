import Foundation

extension LauncherStore {
    func loadAchievementData(client: APIClient? = nil) async throws {
        let api = try client ?? requireClient()
        value.achievementIntent += 1
        let intent = value.achievementIntent
        let archives: [AchievementArchive] = try await api.get("/v1/achievements/archives")
        guard intent == value.achievementIntent else { return }
        guard let archive = archives.first(where: \.selected) ?? archives.first else {
            value.achievementArchives = []; value.achievementEntries = []; value.achievementRevision = 0
            return
        }
        let snapshot: AchievementSnapshot = try await api.get(
            "/v1/achievements/snapshot",
            query: [URLQueryItem(name: "archive_id", value: archive.id)]
        )
        guard intent == value.achievementIntent, snapshot.archive.id == archive.id else { return }
        applyAchievementSnapshot(snapshot, archives: archives)
    }

    func createAchievementArchive(named name: String? = nil) async {
        await perform {
            let title = name?.nonempty ?? "成就档案 \(value.achievementArchives.count + 1)"
            _ = try await requireClient().post(
                "/v1/achievements/archives",
                body: AchievementArchiveRequest(name: title)
            ) as AchievementArchive
            try await loadAchievementData()
        }
    }

    func selectAchievementArchive(_ archive: AchievementArchive) async {
        await perform {
            _ = try await requireClient().post(
                "/v1/achievements/archives/\(archive.id)/select"
            ) as AchievementArchive
            try await loadAchievementData()
        }
    }

    func removeSelectedAchievementArchive() async {
        guard let archive = selectedAchievementArchive else { return }
        await perform {
            try await requireClient().delete("/v1/achievements/archives/\(archive.id)")
            try await loadAchievementData()
        }
    }

    func saveAchievement(_ entry: AchievementEntry, checked: Bool) async {
        guard let archiveId = selectedAchievementArchive?.id else { return }
        let revision = value.achievementRevision
        await perform {
            let item = AchievementItemInput(
                achievementId: entry.achievementId,
                current: entry.current,
                status: checked ? 3 : 0,
                timestamp: checked ? Int(Date().timeIntervalSince1970) : 0
            )
            do {
                let snapshot: AchievementSnapshot = try await requireClient().post(
                    "/v1/achievements",
                    body: AchievementSaveRequest(
                        archiveId: archiveId,
                        expectedRevision: revision,
                        items: [item]
                    )
                )
                guard selectedAchievementArchive?.id == archiveId,
                      value.achievementRevision == revision else { return }
                applyAchievementSnapshot(snapshot, archives: value.achievementArchives)
            } catch let error as APIErrorPayload where error.code == "archive_revision_conflict" {
                try await loadAchievementData()
                throw error
            }
        }
    }

    func importUIAF(from url: URL) async {
        guard let archiveId = selectedAchievementArchive?.id else { return }
        let revision = value.achievementRevision
        await perform {
            let snapshot: AchievementSnapshot = try await requireClient().upload(
                "/v1/achievements/import?archive_id=\(archiveId)&expected_revision=\(revision)",
                json: try UIGFFileIO.read(from: url)
            )
            guard selectedAchievementArchive?.id == archiveId,
                  value.achievementRevision == revision else { return }
            applyAchievementSnapshot(snapshot, archives: value.achievementArchives)
        }
    }

    func exportAchievementUIAF(to url: URL) async {
        await perform {
            let data = try await requireClient().download("/v1/achievements/export")
            try UIGFFileIO.write(data, to: url)
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
}
