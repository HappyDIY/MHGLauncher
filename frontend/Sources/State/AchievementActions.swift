import Foundation

extension LauncherStore {
    func loadAchievementData(client: APIClient? = nil) async throws {
        let api = try client ?? requireClient()
        async let archives: [AchievementArchive] = api.get("/v1/achievements/archives")
        async let entries: [AchievementEntry] = api.get("/v1/achievements/view")
        value.achievementArchives = try await archives
        value.achievementEntries = try await entries
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
        await perform {
            let item = AchievementItemInput(
                achievementId: entry.achievementId,
                current: entry.current,
                status: checked ? 3 : 0,
                timestamp: checked ? Int(Date().timeIntervalSince1970) : 0
            )
            _ = try await requireClient().post(
                "/v1/achievements",
                body: AchievementSaveRequest(archiveId: archiveId, items: [item])
            ) as [AchievementItem]
            try await loadAchievementData()
        }
    }

    func importUIAF(from url: URL) async {
        guard let archiveId = selectedAchievementArchive?.id else { return }
        await perform {
            _ = try await requireClient().upload(
                "/v1/achievements/import?archive_id=\(archiveId)",
                json: try UIGFFileIO.read(from: url)
            ) as [AchievementItem]
            try await loadAchievementData()
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
}
