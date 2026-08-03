import Foundation

extension LauncherStore {
    func loadValueData(force: Bool = true) async {
        guard let uid = selectedRole?.uid else { return }
        guard force || value.loadedRoleUID != uid else { return }
        let generation = companionDataGeneration
        do {
            let client = try requireClient()
            async let loadedCharacters = client.companion.characters(uid)
            async let settings = client.notifications.settings()
            async let goals = client.achievements.goals()
            async let cloudSession = client.cloud.session(uid)
            do {
                try await loadAchievementData(client: client, uid: uid, generation: generation)
                guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
                value.achievementGoals = try await goals
                value.achievementLoaded = true
                value.achievementError = nil
            } catch {
                guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
                value.achievementError = Self.presentableMessage(error)
            }
            do {
                let received = try await loadedCharacters
                guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
                characters = received
                if selectedCharacterId == nil
                    || !characters.contains(where: { $0.avatarId == selectedCharacterId }) {
                    selectedCharacterId = characters.first?.avatarId
                }
            } catch { message = Self.presentableMessage(error) }
            do {
                let loaded = try await settings
                guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
                value.notificationSettings = loaded
                value.notificationConfirmedSettings = loaded
                value.notificationError = nil
            } catch {
                guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
                value.notificationError = Self.presentableMessage(error)
            }
            do {
                let loaded = try await cloudSession
                guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
                value.cloudSession = loaded
            } catch {
                guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
                value.cloudSession = nil
            }
        } catch {
            guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
            value.achievementError = Self.presentableMessage(error)
            value.notificationError = value.achievementError
        }
        if isCurrentCompanionData(uid: uid, generation: generation) {
            value.loadedRoleUID = uid
        }
    }

    func loadGachaResources() async {
        do {
            let client = try requireClient()
            async let syncStatus = client.resources.status()
            let status = try await client.resources.gachaStatus()
            value.resourceSyncStatus = try await syncStatus
            value.gachaResourceStatus = status
            guard status.isReady else {
                value.gachaEvents = []
                await refreshGachaHistoryPresentation()
                return
            }
            value.gachaEvents = try await client.resources.gachaEvents()
            await refreshGachaHistoryPresentation()
        } catch {
            message = Self.presentableMessage(error)
        }
    }

    func installGachaResources() async {
        let previous = value.gachaResourceStatus
        let previousSync = value.resourceSyncStatus
        value.resourceSyncStatus = ResourceSyncStatus(
            state: "syncing", oid: previousSync?.oid,
            lastCheckedAt: previousSync?.lastCheckedAt, lastSuccessAt: previousSync?.lastSuccessAt,
            triggerGameVersion: previousSync?.triggerGameVersion,
            usingLegacyCache: previousSync?.usingLegacyCache ?? false, error: nil
        )
        if previous?.isReady != true {
            value.gachaResourceStatus = GachaResourceStatus(
                state: "installing", version: previous?.version,
                eventCount: previous?.eventCount ?? 0, imageCount: previous?.imageCount ?? 0,
                installedBytes: previous?.installedBytes ?? 0, installedAt: previous?.installedAt
            )
        }
        await perform {
            let client = try requireClient()
            value.resourceSyncStatus = try await client.resources.sync(true)
            if let error = value.resourceSyncStatus?.error { message = error }
            value.gachaResourceStatus = try await client.resources.gachaStatus()
            value.gachaEvents = try await client.resources.gachaEvents()
            if activeWishUID != nil { try await reloadWishes(client: client) }
            if let uid = selectedRole?.uid {
                let generation = companionDataGeneration
                let loaded = try await client.companion.cacheCharacterAssets()
                if isCurrentCompanionData(uid: uid, generation: generation) {
                    characters = loaded
                }
                try await loadAchievementData(client: client, uid: uid, generation: generation)
            }
            await refreshGachaHistoryPresentation()
        }
        if value.gachaResourceStatus?.state == "installing" {
            value.gachaResourceStatus = previous
        }
        if value.resourceSyncStatus?.isSyncing == true {
            value.resourceSyncStatus = previousSync
        }
    }

    func loginCloud() async {
        await perform {
            let result = try await requireClient().cloud.login()
            value.cloudSession = CloudSession(uid: result.uid, tokenRef: result.tokenRef, reverifiedAt: result.reverifiedAt, updatedAt: result.reverifiedAt)
            value.cloudMessage = "已登录 UID \(result.uid)"
        }
    }

    func uploadCloudWishes() async {
        guard let uid = selectedRole?.uid else { return }
        guard value.cloudSession?.uid == uid else {
            message = "请先登录当前角色的云同步服务"
            return
        }
        await perform {
            let count = try await requireClient().cloud.uploadWishes(uid)
            value.cloudMessage = "已上传 \(count) 条记录"
        }
    }

    func retrieveCloudWishes() async {
        guard let uid = selectedRole?.uid else { return }
        guard value.cloudSession?.uid == uid else {
            message = "请先登录当前角色的云同步服务"
            return
        }
        await perform {
            let count = try await requireClient().cloud.retrieveWishes(uid)
            await loadCompanionData()
            value.cloudMessage = "已取回 \(count) 条记录"
        }
    }

}
