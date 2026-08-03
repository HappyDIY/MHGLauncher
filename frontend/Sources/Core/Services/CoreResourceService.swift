import Foundation

actor CoreResourceService {
    private struct Reward: Codable, Sendable { let Count: Int? }
    private struct AchievementMeta: Codable, Sendable {
        let Id: Int
        let Goal: Int
        let Order: Int
        let Title: String
        let Description: String
        let FinishReward: Reward?
        let Progress: Int
        let Version: String
        let Icon: String?
        let IsDailyQuest: Bool?
    }
    private struct GoalMeta: Codable, Sendable {
        let Id: Int
        let Order: Int
        let Name: String
        let FinishReward: Reward?
        let Icon: String
    }
    private struct EventMeta: Codable, Sendable {
        let Name: String
        let Version: String
        let Order: Int
        let Banner: URL?
        let From: Date?
        let To: Date?
        let `Type`: Int
        let UpOrangeList: [Int]
        let UpPurpleList: [Int]
    }
    private struct ItemMeta: Sendable {
        let name: String
        let kind: String
        let rank: Int
        let icon: String?
    }

    private var achievementsCache: [AchievementMeta]?
    private var goalsCache: [GoalMeta]?
    private var eventsCache: [GachaEvent]?
    private var itemsCache: [String: ItemMeta]?

    private let repository: CoreMetadataRepository?
    private var resourceRoot: URL?
    private var statusValue: ResourceSyncStatus

    init(repository: CoreMetadataRepository? = nil, activeSnapshot: CoreMetadataSnapshot? = nil) {
        self.repository = repository
        resourceRoot = activeSnapshot?.root
        statusValue = ResourceSyncStatus(
            state: "ready",
            oid: activeSnapshot?.oid ?? "bundled-swift-v1",
            lastCheckedAt: nil,
            lastSuccessAt: activeSnapshot?.activatedAt,
            triggerGameVersion: nil,
            usingLegacyCache: false,
            error: nil,
            assetState: "ready",
            assetCompleted: 4,
            assetTotal: 4,
            assetFailed: 0,
            initialInstallRequired: false
        )
    }

    func status() -> ResourceSyncStatus {
        statusValue
    }

    func sync(force: Bool) async throws -> ResourceSyncStatus {
        if let repository {
            let checkedAt = Date()
            do {
                let snapshot = try await repository.sync(force: force)
                resourceRoot = snapshot.root
                achievementsCache = nil
                goalsCache = nil
                eventsCache = nil
                itemsCache = nil
                statusValue = ResourceSyncStatus(
                    state: "ready", oid: snapshot.oid, lastCheckedAt: checkedAt,
                    lastSuccessAt: snapshot.activatedAt, triggerGameVersion: nil,
                    usingLegacyCache: false, error: nil, assetState: "ready",
                    assetCompleted: 4, assetTotal: 4, assetFailed: 0,
                    initialInstallRequired: false
                )
            } catch {
                statusValue = ResourceSyncStatus(
                    state: resourceRoot == nil ? "retry" : "ready", oid: statusValue.oid,
                    lastCheckedAt: checkedAt, lastSuccessAt: statusValue.lastSuccessAt,
                    triggerGameVersion: nil, usingLegacyCache: false,
                    error: (error as? LauncherCoreError)?.message ?? "游戏资料同步失败",
                    assetState: "ready", assetCompleted: 4, assetTotal: 4,
                    assetFailed: 0, initialInstallRequired: false
                )
                return statusValue
            }
        }
        _ = try achievements()
        _ = try goals()
        _ = try events()
        _ = try items()
        return statusValue
    }

    func gachaStatus() throws -> GachaResourceStatus {
        let events = try events()
        return GachaResourceStatus(
            state: "ready",
            version: "bundled-swift-v1",
            eventCount: events.count,
            imageCount: try items().count,
            installedBytes: 0,
            installedAt: nil
        )
    }

    func gachaEvents() throws -> [GachaEvent] { try events() }

    func achievementGoals() throws -> [AchievementGoal] {
        try goals().map { value in
            AchievementGoal(
                id: value.Id,
                order: value.Order,
                name: value.Name,
                rewardCount: value.FinishReward?.Count ?? 0,
                iconUrl: resourceURL(category: "achievement", name: value.Icon)
            )
        }
    }

    func achievementEntries(
        archiveID: String,
        saved: [Int: AchievementItem]
    ) throws -> [AchievementEntry] {
        try achievements().map { meta in
            let item = saved[meta.Id]
            return AchievementEntry(
                archiveId: archiveID,
                achievementId: meta.Id,
                current: item?.current ?? 0,
                status: item?.status ?? 0,
                timestamp: item?.timestamp ?? 0,
                updatedAt: item.map { CoreDate.string($0.updatedAt) } ?? "",
                goal: meta.Goal,
                order: meta.Order,
                title: meta.Title,
                description: meta.Description,
                progress: meta.Progress,
                version: meta.Version,
                rewardCount: meta.FinishReward?.Count ?? 0,
                iconUrl: resourceURL(category: "achievement", name: meta.Icon ?? ""),
                isDailyQuest: meta.IsDailyQuest ?? false
            )
        }
    }

    func achievementProgress() throws -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: try achievements().map { ($0.Id, $0.Progress) })
    }

    func enrich(_ record: WishRecord) throws -> WishRecord {
        guard let item = try items()[record.itemId] else { return record }
        return WishRecord(
            id: record.id,
            uid: record.uid,
            gachaType: record.gachaType,
            itemId: record.itemId,
            name: record.name.isEmpty ? item.name : record.name,
            itemType: record.itemType.isEmpty ? item.kind : record.itemType,
            rank: record.rank == 0 ? item.rank : record.rank,
            time: record.time,
            iconUrl: resourceURL(category: item.kind == "角色" ? "avatar" : "weapon", name: item.icon ?? "")
        )
    }

    private func achievements() throws -> [AchievementMeta] {
        if let achievementsCache { return achievementsCache }
        let result: [AchievementMeta] = try decode("achievement", extension: "json")
        guard result.count <= 20_000 else { throw metadataError() }
        achievementsCache = result
        return result
    }

    private func goals() throws -> [GoalMeta] {
        if let goalsCache { return goalsCache }
        let result: [GoalMeta] = try decode("achievement_goals", extension: "json")
        guard result.count <= 20_000 else { throw metadataError() }
        goalsCache = result
        return result
    }

    private func events() throws -> [GachaEvent] {
        if let eventsCache { return eventsCache }
        let source: [EventMeta] = try decode("gacha_events", extension: "json")
        let itemValues = try items()
        let result = source.map { event in
            let orange = event.UpOrangeList.compactMap { itemValues[String($0)]?.name }
            let purple = event.UpPurpleList.compactMap { itemValues[String($0)]?.name }
            return GachaEvent(
                id: "\(event.Version)-\(event.Order)-\(event.`Type`)-\(event.Name)",
                version: event.Version,
                gachaType: String(event.`Type`),
                name: event.Name,
                startedAt: event.From,
                endedAt: event.To,
                orangeUp: orange,
                purpleUp: purple,
                orangeUpIcons: Dictionary(uniqueKeysWithValues: event.UpOrangeList.compactMap { id in
                    guard let item = itemValues[String(id)], let url = resourceURL(
                        category: item.kind == "角色" ? "avatar" : "weapon", name: item.icon ?? ""
                    ) else { return nil }
                    return (item.name, url)
                }),
                purpleUpIcons: Dictionary(uniqueKeysWithValues: event.UpPurpleList.compactMap { id in
                    guard let item = itemValues[String(id)], let url = resourceURL(
                        category: item.kind == "角色" ? "avatar" : "weapon", name: item.icon ?? ""
                    ) else { return nil }
                    return (item.name, url)
                }),
                bannerUrl: event.Banner,
                updatedAt: event.To ?? event.From ?? .distantPast
            )
        }
        eventsCache = result
        return result
    }

    private func items() throws -> [String: ItemMeta] {
        if let itemsCache { return itemsCache }
        let data = try resourceData("gacha_items", extension: "json")
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: [Any]] ?? [:]
        guard raw.count <= 20_000 else { throw metadataError() }
        let result = raw.reduce(into: [String: ItemMeta]()) { output, pair in
            guard pair.value.count >= 3,
                  let name = pair.value[0] as? String,
                  let kind = pair.value[1] as? String,
                  let rank = pair.value[2] as? Int else { return }
            output[pair.key] = ItemMeta(
                name: name,
                kind: kind,
                rank: rank,
                icon: pair.value.count > 3 ? pair.value[3] as? String : nil
            )
        }
        guard result.count == raw.count else { throw metadataError() }
        itemsCache = result
        return result
    }

    private func decode<T: Decodable>(_ name: String, extension fileExtension: String) throws -> T {
        let decoder = JSONDecoder.api
        return try decoder.decode(T.self, from: resourceData(name, extension: fileExtension))
    }

    private func resourceData(_ name: String, extension fileExtension: String) throws -> Data {
        if let resourceRoot {
            let url = resourceRoot.appending(path: "\(name).\(fileExtension)")
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? 0) <= 8 * 1024 * 1024 else { throw metadataError() }
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "CoreMetadata"
        ) ?? Bundle.module.url(forResource: name, withExtension: fileExtension) else {
            throw metadataError()
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 8 * 1024 * 1024 else {
            throw metadataError()
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func resourceURL(category: String, name: String) -> URL? {
        guard name.range(of: #"^[A-Za-z0-9_]{1,128}$"#, options: .regularExpression) != nil else {
            return nil
        }
        var components = URLComponents()
        components.scheme = MHGResourceURL.scheme
        components.host = category
        components.path = "/\(name)"
        return components.url
    }

    private func metadataError() -> LauncherCoreError {
        LauncherCoreError(code: "metadata_invalid", message: "内置游戏资料无效")
    }
}
