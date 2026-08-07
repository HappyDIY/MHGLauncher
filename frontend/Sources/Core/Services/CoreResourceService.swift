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
    private struct CharacterAssets: Codable, Sendable {
        let avatars: [String: String]
        let weapons: [String: String]
        let reliquaries: [String: String]
        let skills: [String: String]
        let talents: [String: String]

        static let empty = CharacterAssets(
            avatars: [:], weapons: [:], reliquaries: [:], skills: [:], talents: [:]
        )

        var count: Int {
            avatars.count + weapons.count + reliquaries.count + skills.count + talents.count
        }
    }

    private struct LegacyItem: Sendable {
        let name: String
        let kind: String
        let rank: Int
        let icon: String?
    }

    private struct LegacyEvent: Sendable {
        let id: String
        let version: String
        let gachaType: String
        let name: String
        let startedAt: Date?
        let endedAt: Date?
        let orangeUp: [String]
        let purpleUp: [String]
        let banner: String?
        let updatedAt: Date
    }

    private struct LegacyCatalog: Sendable {
        let version: String
        let events: [LegacyEvent]
        let items: [String: LegacyItem]
        let characterAssets: CharacterAssets
        let imageFiles: Set<String>
    }

    private var achievementsCache: [AchievementMeta]?
    private var goalsCache: [GoalMeta]?
    private var eventsCache: [GachaEvent]?
    private var itemsCache: [String: ItemMeta]?
    private var characterAssetsCache: CharacterAssets?

    private let repository: CoreMetadataRepository?
    private let images: CoreImageService?
    private let fixtureMode: Bool
    private let legacyRoot: URL?
    private let legacyAchievementRoot: URL?
    private var resourceRoot: URL?
    private var statusValue: ResourceSyncStatus
    private var legacyCatalogCache: LegacyCatalog?

    init(
        repository: CoreMetadataRepository? = nil,
        activeSnapshot: CoreMetadataSnapshot? = nil,
        fixtureMode: Bool = false,
        dataDirectory: URL? = nil,
        images: CoreImageService? = nil
    ) {
        self.repository = repository
        self.images = images
        self.fixtureMode = fixtureMode
        legacyRoot = dataDirectory?.appending(path: "resources/gacha-history", directoryHint: .isDirectory)
        legacyAchievementRoot = dataDirectory?.appending(path: "resources/achievements", directoryHint: .isDirectory)
        resourceRoot = activeSnapshot?.root
        statusValue = ResourceSyncStatus(
            state: "ready",
            oid: activeSnapshot?.oid ?? (fixtureMode ? "fixture" : "bundled-swift-v1"),
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
        applyLegacyStatusIfNeeded()
        statusValue
    }

    private func ensure() async {
        guard let repository, let snapshot = await repository.ensure() else { return }
        guard resourceRoot != snapshot.root else { return }
        resourceRoot = snapshot.root
        achievementsCache = nil
        goalsCache = nil
        eventsCache = nil
        itemsCache = nil
        characterAssetsCache = nil
        legacyCatalogCache = nil
        statusValue = ResourceSyncStatus(
            state: "ready", oid: snapshot.oid, lastCheckedAt: Date(),
            lastSuccessAt: snapshot.activatedAt, triggerGameVersion: nil,
            usingLegacyCache: false, error: nil, assetState: "ready",
            assetCompleted: 4, assetTotal: 4, assetFailed: 0,
            initialInstallRequired: false
        )
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
                characterAssetsCache = nil
                legacyCatalogCache = nil
                statusValue = ResourceSyncStatus(
                    state: "ready", oid: snapshot.oid, lastCheckedAt: checkedAt,
                    lastSuccessAt: snapshot.activatedAt, triggerGameVersion: nil,
                    usingLegacyCache: false, error: nil, assetState: "ready",
                    assetCompleted: 4, assetTotal: 4, assetFailed: 0,
                    initialInstallRequired: false
                )
            } catch {
                applyLegacyStatusIfNeeded()
                statusValue = ResourceSyncStatus(
                    state: resourceRoot == nil && !hasUsableLegacyCatalog ? "retry" : "ready",
                    oid: statusValue.oid,
                    lastCheckedAt: checkedAt, lastSuccessAt: statusValue.lastSuccessAt,
                    triggerGameVersion: nil, usingLegacyCache: statusValue.usingLegacyCache,
                    error: (error as? LauncherCoreError)?.message ?? "游戏资料同步失败",
                    assetState: "ready", assetCompleted: 4, assetTotal: 4,
                    assetFailed: 0, initialInstallRequired: false
                )
                return statusValue
            }
        }
        _ = try achievements()
        _ = try goals()
        _ = try await events()
        _ = try items()
        return statusValue
    }

    func gachaStatus() async throws -> GachaResourceStatus {
        await ensure()
        applyLegacyStatusIfNeeded()
        if hasLegacyCatalogFile && legacyCatalog() == nil {
            return GachaResourceStatus(
                state: "missing", version: nil, eventCount: 0, imageCount: 0,
                installedBytes: 0, installedAt: nil
            )
        }
        let events = try await events()
        let assets = try characterAssets()
        let imageCount = legacyCatalog()?.imageFiles.count ?? assets.count
        return GachaResourceStatus(
            state: "ready",
            version: statusValue.oid,
            eventCount: events.count,
            imageCount: imageCount,
            installedBytes: 0,
            installedAt: statusValue.lastSuccessAt
        )
    }

    func gachaEvents() async throws -> [GachaEvent] {
        await ensure()
        try await events().sorted {
            let left = $0.startedAt ?? .distantPast
            let right = $1.startedAt ?? .distantPast
            if left != right { return left > right }
            return $0.name < $1.name
        }
    }

    func achievementGoals() async throws -> [AchievementGoal] {
        await ensure()
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
    ) async throws -> [AchievementEntry] {
        await ensure()
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

    func achievementProgress() async throws -> [Int: Int] {
        await ensure()
        Dictionary(try achievements().map { ($0.Id, $0.Progress) }, uniquingKeysWith: { _, latest in latest })
    }

    func enrich(_ record: WishRecord) async throws -> WishRecord {
        await ensure()
        let values = (try? items()) ?? [:]
        let resolved: (id: String, item: ItemMeta)? = values[record.itemId].map {
            (record.itemId, $0)
        } ?? record.name.nonempty.flatMap { name in
            values.first { $0.value.name == name }.map { ($0.key, $0.value) }
        }
        guard let resolved else {
            return WishRecord(
                id: record.id,
                uid: record.uid,
                gachaType: record.gachaType,
                uigfGachaType: record.uigfGachaType,
                itemId: record.itemId,
                name: record.name,
                itemType: record.itemType,
                rank: record.rank,
                time: record.time,
                iconUrl: nil
            )
        }
        let item = resolved.item
        return WishRecord(
            id: record.id,
            uid: record.uid,
            gachaType: record.gachaType,
            uigfGachaType: record.uigfGachaType,
            itemId: resolved.id,
            name: record.name.isEmpty ? item.name : record.name,
            itemType: record.itemType.isEmpty ? item.kind : record.itemType,
            rank: record.rank == 0 ? item.rank : record.rank,
            time: record.time,
            iconUrl: resourceURL(category: item.kind == "角色" ? "avatar" : "weapon", name: item.icon ?? "")
        )
    }

    func enrich(_ character: GameCharacter) async throws -> GameCharacter {
        await ensure()
        let values = (try? items()) ?? [:]
        let assets = (try? characterAssets()) ?? .empty
        let baseWeapon = character.payload?.base?.weapon.map { value in
            CharacterWeapon(
                id: value.id,
                name: value.name,
                icon: characterIcon(
                    value.icon, id: value.id, assets: assets, values: values, category: "weapon"
                ),
                rarity: value.rarity,
                level: value.level,
                affixLevel: value.affixLevel,
                mainProperty: value.mainProperty,
                subProperty: value.subProperty
            )
        }
        let base = character.payload?.base.map { value in
            CharacterBase(
                id: value.id,
                name: value.name,
                icon: characterIcon(
                    value.icon, id: value.id, assets: assets, values: values, category: "avatar"
                ),
                rarity: value.rarity,
                level: value.level,
                element: value.element,
                fetter: value.fetter,
                weapon: baseWeapon
            )
        }
        let weapon = character.payload?.weapon.map { value in
            CharacterWeapon(
                id: value.id,
                name: value.name,
                icon: characterIcon(
                    value.icon, id: value.id, assets: assets, values: values, category: "weapon"
                ),
                rarity: value.rarity,
                level: value.level,
                affixLevel: value.affixLevel,
                mainProperty: value.mainProperty,
                subProperty: value.subProperty
            )
        }
        let payload = character.payload.map { value in
            CharacterPayload(
                base: base,
                weapon: weapon,
                relics: value.relics?.map { relic in
                    CharacterReliquary(
                        assetId: relic.assetId,
                        name: relic.name,
                        icon: characterIcon(
                            relic.icon, id: relic.assetId, assets: assets, values: values, category: "relic"
                        ),
                        setName: relic.setName,
                        rarity: relic.rarity,
                        level: relic.level,
                        pos: relic.pos,
                        mainProperty: relic.mainProperty,
                        subProperties: relic.subProperties
                    )
                },
                constellations: value.constellations?.map { constellation in
                    CharacterConstellation(
                        assetId: constellation.assetId,
                        name: constellation.name,
                        icon: characterIcon(
                            constellation.icon,
                            id: constellation.assetId,
                            assets: assets,
                            values: values,
                            category: "talent"
                        ),
                        isActivated: constellation.isActivated,
                        description: constellation.description
                    )
                },
                selectedProperties: value.selectedProperties,
                skills: value.skills?.map { skill in
                    CharacterSkill(
                        skillId: skill.skillId,
                        name: skill.name,
                        icon: characterIcon(
                            skill.icon, id: skill.skillId, assets: assets, values: values, category: "skill"
                        ),
                        skillType: skill.skillType,
                        level: skill.level,
                        maxLevel: skill.maxLevel,
                        desc: skill.desc
                    )
                },
                recommendRelicProperty: value.recommendRelicProperty,
                additionalFields: value.additionalFields,
                rawFields: value.rawFields
            )
        }
        let presentedPayload = await localizedPayload(payload)
        let icon = fixtureMode
            ? nil
            : await localizedImage(characterIcon(
                character.iconUrl,
                id: Int(character.avatarId),
                assets: assets,
                values: values,
                category: "avatar",
                fallbackOnMissingAsset: true
            ))
        return GameCharacter(
            uid: character.uid,
            avatarId: character.avatarId,
            name: character.name,
            element: character.element,
            level: character.level,
            rarity: character.rarity,
            constellation: character.constellation,
            fetter: character.fetter,
            weaponName: character.weaponName,
            weaponLevel: character.weaponLevel,
            iconUrl: icon,
            payload: presentedPayload,
            updatedAt: character.updatedAt
        )
    }

    private func localizedPayload(_ value: CharacterPayload?) async -> CharacterPayload? {
        guard let value else { return nil }
        return CharacterPayload(
            base: await localizedBase(value.base),
            weapon: await localizedWeapon(value.weapon),
            relics: await localizedRelics(value.relics),
            constellations: await localizedConstellations(value.constellations),
            selectedProperties: value.selectedProperties,
            skills: await localizedSkills(value.skills),
            recommendRelicProperty: value.recommendRelicProperty,
            additionalFields: await localizedAdditionalFields(value.additionalFields),
            rawFields: await localizedRawFields(value.rawFields)
        )
    }

    private func localizedBase(_ value: CharacterBase?) async -> CharacterBase? {
        guard let value else { return nil }
        return CharacterBase(
            id: value.id, name: value.name, icon: await localizedImage(value.icon),
            rarity: value.rarity, level: value.level, element: value.element,
            fetter: value.fetter, weapon: await localizedWeapon(value.weapon)
        )
    }

    private func localizedWeapon(_ value: CharacterWeapon?) async -> CharacterWeapon? {
        guard let value else { return nil }
        return CharacterWeapon(
            id: value.id, name: value.name, icon: await localizedImage(value.icon),
            rarity: value.rarity, level: value.level, affixLevel: value.affixLevel,
            mainProperty: value.mainProperty, subProperty: value.subProperty
        )
    }

    private func localizedRelics(_ values: [CharacterReliquary]?) async -> [CharacterReliquary]? {
        guard let values else { return nil }
        var result: [CharacterReliquary] = []
        result.reserveCapacity(values.count)
        for value in values {
            result.append(CharacterReliquary(
                assetId: value.assetId, name: value.name, icon: await localizedImage(value.icon),
                setName: value.setName, rarity: value.rarity, level: value.level, pos: value.pos,
                mainProperty: value.mainProperty, subProperties: value.subProperties
            ))
        }
        return result
    }

    private func localizedSkills(_ values: [CharacterSkill]?) async -> [CharacterSkill]? {
        guard let values else { return nil }
        var result: [CharacterSkill] = []
        result.reserveCapacity(values.count)
        for value in values {
            result.append(CharacterSkill(
                skillId: value.skillId, name: value.name, icon: await localizedImage(value.icon),
                skillType: value.skillType, level: value.level, maxLevel: value.maxLevel, desc: value.desc
            ))
        }
        return result
    }

    private func localizedConstellations(_ values: [CharacterConstellation]?) async -> [CharacterConstellation]? {
        guard let values else { return nil }
        var result: [CharacterConstellation] = []
        result.reserveCapacity(values.count)
        for value in values {
            result.append(CharacterConstellation(
                assetId: value.assetId, name: value.name, icon: await localizedImage(value.icon),
                isActivated: value.isActivated, description: value.description
            ))
        }
        return result
    }

    private func localizedAdditionalFields(_ values: [String: JSONValue]) async -> [String: JSONValue] {
        guard !values.isEmpty else { return values }
        var result: [String: JSONValue] = [:]
        result.reserveCapacity(values.count)
        for (key, value) in values {
            result[key] = await localizedJSON(value, key: key)
        }
        return result
    }

    private func localizedRawFields(_ values: [String: JSONValue]) async -> [String: JSONValue] {
        guard !values.isEmpty else { return values }
        var result: [String: JSONValue] = [:]
        result.reserveCapacity(values.count)
        for (key, value) in values {
            result[key] = await localizedJSON(value, key: key)
        }
        return result
    }

    private func localizedJSON(_ value: JSONValue, key: String? = nil) async -> JSONValue {
        switch value {
        case .string(let raw) where ["icon", "image", "side_icon"].contains(key):
            guard !fixtureMode, let url = URL(string: raw), let images,
                  let local = await images.cachedURL(for: url) else { return .null }
            return .string(local.absoluteString)
        case .object(let values):
            var result: [String: JSONValue] = [:]
            result.reserveCapacity(values.count)
            for (childKey, child) in values {
                result[childKey] = await localizedJSON(child, key: childKey)
            }
            return .object(result)
        case .array(let values):
            var result: [JSONValue] = []
            result.reserveCapacity(values.count)
            for child in values { result.append(await localizedJSON(child)) }
            return .array(result)
        default:
            return value
        }
    }

    private func localizedImage(_ value: URL?) async -> URL? {
        guard let value else { return nil }
        guard !fixtureMode else { return nil }
        if value.scheme == MHGResourceURL.scheme { return value }
        return await images?.cachedURL(for: value)
    }

    private func characterIcon(
        _ fallback: URL?,
        id: Int?,
        assets: CharacterAssets,
        values: [String: ItemMeta],
        category: String,
        fallbackOnMissingAsset: Bool = false
    ) -> URL? {
        guard !fixtureMode else { return nil }
        guard let id else {
            return resourceRoot == nil || fallbackOnMissingAsset ? fallback : nil
        }
        let assetName: String?
        switch category {
        case "avatar": assetName = assets.avatars[String(id)] ?? values[String(id)]?.icon
        case "weapon": assetName = assets.weapons[String(id)] ?? values[String(id)]?.icon
        case "relic": assetName = assets.reliquaries[String(id)]
        case "skill": assetName = assets.skills[String(id)]
        case "talent": assetName = assets.talents[String(id)]
        default: assetName = nil
        }
        let preserveFallback = fallbackOnMissingAsset || resourceRoot == nil
        return assetName.flatMap { resourceURL(category: category, name: $0) }
            ?? (preserveFallback ? fallback : nil)
    }

    private func achievements() throws -> [AchievementMeta] {
        if let achievementsCache { return achievementsCache }
        let result: [AchievementMeta]
        if resourceRoot == nil, hasLegacyAchievementFile {
            guard let data = legacyData(named: "Achievement.json") else { throw metadataError() }
            result = try decode(AchievementMeta.self, from: data)
        } else {
            result = try decode("achievement", extension: "json")
        }
        guard result.count <= 20_000 else { throw metadataError() }
        achievementsCache = result
        return result
    }

    private func goals() throws -> [GoalMeta] {
        if let goalsCache { return goalsCache }
        let result: [GoalMeta]
        if resourceRoot == nil, hasLegacyAchievementFile {
            guard let data = legacyData(named: "AchievementGoal.json") else { throw metadataError() }
            result = try decode(GoalMeta.self, from: data)
        } else {
            result = try decode("achievement_goals", extension: "json")
        }
        guard result.count <= 20_000 else { throw metadataError() }
        goalsCache = result
        return result
    }

    private func events() async throws -> [GachaEvent] {
        if let eventsCache { return eventsCache }
        if resourceRoot == nil, hasLegacyCatalogFile {
            guard let legacy = legacyCatalog() else { throw legacyResourceError() }
            let result = legacy.events.map { event in
                GachaEvent(
                    id: event.id,
                    version: event.version,
                    gachaType: event.gachaType,
                    name: event.name,
                    startedAt: event.startedAt,
                    endedAt: event.endedAt,
                    orangeUp: event.orangeUp,
                    purpleUp: event.purpleUp,
                    orangeUpIcons: nil,
                    purpleUpIcons: nil,
                    bannerUrl: event.banner.flatMap(legacyResourceURL),
                    updatedAt: event.updatedAt
                )
            }
            eventsCache = result
            return result
        }
        let source: [EventMeta] = try decode("gacha_events", extension: "json")
        guard source.count <= 20_000,
              source.allSatisfy({ $0.UpOrangeList.count <= 256 && $0.UpPurpleList.count <= 256 }) else {
            throw metadataError()
        }
        let itemValues = try items()
        var result: [GachaEvent] = []
        result.reserveCapacity(source.count)
        for event in source {
            let orange = event.UpOrangeList.compactMap { itemValues[String($0)]?.name }
            let purple = event.UpPurpleList.compactMap { itemValues[String($0)]?.name }
            result.append(GachaEvent(
                id: "\(event.Version)-\(event.Order)-\(event.`Type`)-\(event.Name)",
                version: event.Version,
                gachaType: String(event.`Type`),
                name: event.Name,
                startedAt: event.From,
                endedAt: event.To,
                orangeUp: orange,
                purpleUp: purple,
                orangeUpIcons: Dictionary(event.UpOrangeList.compactMap { id in
                    guard let item = itemValues[String(id)], let url = resourceURL(
                        category: item.kind == "角色" ? "avatar" : "weapon", name: item.icon ?? ""
                    ) else { return nil }
                    return (item.name, url)
                }, uniquingKeysWith: { first, _ in first }),
                purpleUpIcons: Dictionary(event.UpPurpleList.compactMap { id in
                    guard let item = itemValues[String(id)], let url = resourceURL(
                        category: item.kind == "角色" ? "avatar" : "weapon", name: item.icon ?? ""
                    ) else { return nil }
                    return (item.name, url)
                }, uniquingKeysWith: { first, _ in first }),
                bannerUrl: fixtureMode ? nil : await localizedRemoteURL(event.Banner, digest: statusValue.oid),
                updatedAt: event.To ?? .distantPast
            ))
        }
        eventsCache = result
        return result
    }

    private func localizedRemoteURL(_ value: URL?, digest: String? = nil) async -> URL? {
        guard let value else { return nil }
        guard !fixtureMode else { return nil }
        return await images?.cachedURL(for: value, digest: digest)
    }

    private func items() throws -> [String: ItemMeta] {
        if let itemsCache { return itemsCache }
        if resourceRoot == nil, hasLegacyCatalogFile {
            guard let legacy = legacyCatalog() else { throw legacyResourceError() }
            let result = legacy.items.mapValues { value in
                ItemMeta(name: value.name, kind: value.kind, rank: value.rank, icon: value.icon)
            }
            itemsCache = result
            return result
        }
        let data = try resourceData("gacha_items", extension: "json")
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let raw = object as? [String: [Any]] else { throw metadataError() }
        guard raw.count <= 20_000 else { throw metadataError() }
        let result = raw.reduce(into: [String: ItemMeta]()) { output, pair in
            guard pair.value.count >= 3,
                  let name = pair.value[0] as? String,
                  let kind = pair.value[1] as? String,
                  let rank = pair.value[2] as? Int,
                  name.utf8.count <= 256, kind.utf8.count <= 64,
                  (0...5).contains(rank) else { return }
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

    private func characterAssets() throws -> CharacterAssets {
        if let characterAssetsCache { return characterAssetsCache }
        let result: CharacterAssets
        if resourceRoot == nil, hasLegacyCatalogFile {
            guard let legacy = legacyCatalog() else { throw legacyResourceError() }
            result = legacy.characterAssets
        } else {
            result = (try? decode("character_assets", extension: "json")) ?? .empty
        }
        guard result.avatars.count <= 20_000,
              result.weapons.count <= 20_000,
              result.reliquaries.count <= 20_000,
              result.skills.count <= 20_000,
              result.talents.count <= 20_000 else {
            throw metadataError()
        }
        characterAssetsCache = result
        return result
    }

    private func decode<T: Decodable>(_ name: String, extension fileExtension: String) throws -> T {
        let decoder = JSONDecoder.api
        return try decoder.decode(T.self, from: resourceData(name, extension: fileExtension))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder.api.decode(type, from: data)
    }

    private func resourceData(_ name: String, extension fileExtension: String) throws -> Data {
        if let resourceRoot {
            let url = resourceRoot.appending(path: "\(name).\(fileExtension)")
            guard GameFilesystem.regularFile(url) else { throw metadataError() }
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

    private func resourceURL(category: String, name: String, digest: String? = nil) -> URL? {
        guard !fixtureMode else { return nil }
        if name.hasPrefix("images/") {
            return legacyResourceURL(name)
        }
        guard name.range(of: #"^[A-Za-z0-9_]{1,128}$"#, options: .regularExpression) != nil else {
            return nil
        }
        var components = URLComponents()
        components.scheme = MHGResourceURL.scheme
        components.host = category
        let version = digest ?? statusValue.oid ?? "bundled"
        guard version.range(of: #"^[A-Za-z0-9._-]{1,128}$"#, options: .regularExpression) != nil else {
            return nil
        }
        components.path = "/\(name)/\(version)"
        return components.url
    }

    private func legacyResourceURL(_ name: String) -> URL? {
        guard Self.validLegacyResourceName(name),
              let root = legacyRoot,
              GameFilesystem.regularFile(root.appending(path: name)) else { return nil }
        var components = URLComponents()
        components.scheme = MHGResourceURL.scheme
        components.host = "legacy"
        components.path = "/\(name)"
        return components.url
    }

    private var hasLegacyCatalogFile: Bool {
        guard let root = legacyRoot else { return false }
        return GameFilesystem.regularFile(root.appending(path: "catalog.json"))
    }

    private var hasUsableLegacyCatalog: Bool {
        legacyCatalog() != nil
    }

    private func applyLegacyStatusIfNeeded() {
        guard resourceRoot == nil, let legacy = legacyCatalog() else { return }
        statusValue = ResourceSyncStatus(
            state: "ready", oid: legacy.version, lastCheckedAt: statusValue.lastCheckedAt,
            lastSuccessAt: statusValue.lastSuccessAt, triggerGameVersion: nil,
            usingLegacyCache: true, error: nil, assetState: "ready",
            assetCompleted: 4, assetTotal: 4, assetFailed: 0, initialInstallRequired: false
        )
    }

    private func legacyCatalog() -> LegacyCatalog? {
        if let legacyCatalogCache { return legacyCatalogCache }
        guard let root = legacyRoot,
              let data = try? boundedData(root.appending(path: "catalog.json")) else {
            return nil
        }
        do {
            let value = try Self.parseLegacyCatalog(data, root: root)
            legacyCatalogCache = value
            return value
        } catch {
            return nil
        }
    }

    private func legacyData(named name: String) -> Data? {
        guard let root = legacyAchievementRoot else { return nil }
        let url = root.appending(path: name)
        guard GameFilesystem.regularFile(url),
              let data = try? boundedData(url) else { return nil }
        return data
    }

    private var hasLegacyAchievementFile: Bool {
        guard let root = legacyAchievementRoot else { return false }
        return GameFilesystem.regularFile(root.appending(path: "Achievement.json"))
            || GameFilesystem.regularFile(root.appending(path: "AchievementGoal.json"))
    }

    private func boundedData(_ url: URL) throws -> Data {
        guard GameFilesystem.regularFile(url) else { throw metadataError() }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 16 * 1024 * 1024 else {
            throw metadataError()
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func parseLegacyCatalog(_ data: Data, root: URL) throws -> LegacyCatalog {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["schema_version", "version", "metadata_revision", "events", "items", "character_assets"]),
              (object["schema_version"] as? NSNumber)?.intValue == 2,
              let version = object["version"] as? String,
              let revision = object["metadata_revision"] as? String,
              !version.isEmpty, version.utf8.count <= 64,
              !revision.isEmpty, revision.utf8.count <= 64,
              let rawEvents = object["events"] as? [[String: Any]], rawEvents.count <= 10_000,
              let rawItems = object["items"] as? [String: [Any]], rawItems.count <= 20_000,
              let rawAssets = object["character_assets"] as? [String: [String: String]],
              Set(rawAssets.keys) == Set(["avatars", "weapons", "reliquaries", "skills", "talents"]) else {
            throw legacyMetadataError()
        }

        let events = try rawEvents.map { value -> LegacyEvent in
            guard Set(value.keys) == Set(["id", "version", "gacha_type", "name", "started_at", "ended_at", "orange_up", "purple_up", "banner_file", "updated_at"]),
                  let id = value["id"] as? String,
                  let eventVersion = value["version"] as? String,
                  let gachaType = value["gacha_type"] as? String,
                  let name = value["name"] as? String,
                  let orange = value["orange_up"] as? [String],
                  let purple = value["purple_up"] as? [String],
                  let updated = value["updated_at"] as? String,
                  id.utf8.count <= 256, eventVersion.utf8.count <= 64,
                  gachaType.utf8.count <= 16, name.utf8.count <= 256,
                  orange.count <= 1_000, purple.count <= 1_000,
                  orange.allSatisfy({ $0.utf8.count <= 256 }),
                  purple.allSatisfy({ $0.utf8.count <= 256 }),
                  let updatedAt = Self.legacyDate(updated) else {
                throw legacyMetadataError()
            }
            let banner: String?
            if let raw = value["banner_file"], !(raw is NSNull) {
                guard let file = raw as? String, validLegacyResourceName(file) else {
                    throw legacyMetadataError()
                }
                banner = file
            } else {
                banner = nil
            }
            return LegacyEvent(
                id: id, version: eventVersion, gachaType: gachaType, name: name,
                startedAt: (value["started_at"] as? String).flatMap(Self.legacyDate),
                endedAt: (value["ended_at"] as? String).flatMap(Self.legacyDate),
                orangeUp: orange, purpleUp: purple, banner: banner, updatedAt: updatedAt
            )
        }

        var items: [String: LegacyItem] = [:]
        for (id, value) in rawItems {
            guard id.range(of: #"^\d{1,19}$"#, options: .regularExpression) != nil,
                  value.count >= 3, value.count <= 4,
                  let name = value[0] as? String,
                  let kind = value[1] as? String,
                  let rank = (value[2] as? NSNumber)?.intValue,
                  name.utf8.count <= 256, kind.utf8.count <= 64,
                  (0...5).contains(rank) else { throw legacyMetadataError() }
            let icon: String?
            if value.count > 3, !(value[3] is NSNull) {
                guard let file = value[3] as? String, validLegacyResourceName(file) else {
                    throw legacyMetadataError()
                }
                icon = file
            } else {
                icon = nil
            }
            items[id] = LegacyItem(name: name, kind: kind, rank: rank, icon: icon)
        }

        var assets = CharacterAssets.empty
        var imageFiles = Set<String>()
        var requiredFiles = Set<String>()
        for (key, values) in rawAssets {
            guard values.count <= 20_000 else { throw legacyMetadataError() }
            for (id, file) in values {
                guard id.utf8.count <= 64, validLegacyResourceName(file) else {
                    throw legacyMetadataError()
                }
                requiredFiles.insert(file)
            }
            switch key {
            case "avatars": assets = CharacterAssets(
                avatars: values, weapons: assets.weapons, reliquaries: assets.reliquaries,
                skills: assets.skills, talents: assets.talents
            )
            case "weapons": assets = CharacterAssets(
                avatars: assets.avatars, weapons: values, reliquaries: assets.reliquaries,
                skills: assets.skills, talents: assets.talents
            )
            case "reliquaries": assets = CharacterAssets(
                avatars: assets.avatars, weapons: assets.weapons, reliquaries: values,
                skills: assets.skills, talents: assets.talents
            )
            case "skills": assets = CharacterAssets(
                avatars: assets.avatars, weapons: assets.weapons, reliquaries: assets.reliquaries,
                skills: values, talents: assets.talents
            )
            case "talents": assets = CharacterAssets(
                avatars: assets.avatars, weapons: assets.weapons, reliquaries: assets.reliquaries,
                skills: assets.skills, talents: values
            )
            default: throw legacyMetadataError()
            }
        }
        for event in events { if let banner = event.banner { imageFiles.insert(banner) } }
        for item in items.values { if let icon = item.icon { imageFiles.insert(icon) } }
        requiredFiles.formUnion(imageFiles)
        for file in requiredFiles {
            let url = root.appending(path: file)
            guard GameFilesystem.regularFile(url) else { throw legacyMetadataError() }
        }
        return LegacyCatalog(
            version: version, events: events, items: items,
            characterAssets: assets, imageFiles: imageFiles
        )
    }

    private static func legacyDate(_ value: String) -> Date? {
        guard value.utf8.count <= 128, !value.isEmpty else { return nil }
        let date = CoreDate.parse(value)
        if date != .distantPast { return date }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func validLegacyResourceName(_ value: String) -> Bool {
        value.range(of: #"^images/[a-f0-9]{64}\.img$"#, options: .regularExpression) != nil
    }

    private static func legacyMetadataError() -> LauncherCoreError {
        LauncherCoreError(code: "metadata_invalid", message: "旧版游戏资料缓存已损坏")
    }

    private func legacyResourceError() -> LauncherCoreError {
        LauncherCoreError(code: "gacha_resource_missing", message: "暂无可用游戏资料，请刷新后重试")
    }

    private func metadataError() -> LauncherCoreError {
        LauncherCoreError(code: "metadata_invalid", message: "内置游戏资料无效")
    }
}
