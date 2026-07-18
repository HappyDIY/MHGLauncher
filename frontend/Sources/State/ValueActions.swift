import Foundation

extension LauncherStore {
    func loadValueData() async {
        guard let uid = selectedRole?.uid else { return }
        let generation = companionDataGeneration
        do {
            let client = try requireClient()
            async let loadedCharacters: [GameCharacter] = client.get(
                "/v1/characters", query: [URLQueryItem(name: "uid", value: uid)]
            )
            async let settings: NotificationSettings = client.get("/v1/notifications/settings")
            async let goals: [AchievementGoal] = client.get("/v1/achievements/goals")
            async let cloudSession: CloudSession? = client.get(
                "/v1/cloud/session", query: [URLQueryItem(name: "uid", value: uid)]
            )
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
    }

    func loadGachaResources() async {
        do {
            let status: GachaResourceStatus = try await requireClient().get("/v1/gacha-resources/status")
            value.gachaResourceStatus = status
            guard status.isReady else {
                value.gachaEvents = []
                await refreshGachaHistoryPresentation()
                return
            }
            value.gachaEvents = try await requireClient().get("/v1/gacha-events")
            await refreshGachaHistoryPresentation()
        } catch {
            message = Self.presentableMessage(error)
        }
    }

    func installGachaResources() async {
        let previous = value.gachaResourceStatus
        value.gachaResourceStatus = GachaResourceStatus(
            state: "installing",
            version: previous?.version,
            eventCount: previous?.eventCount ?? 0,
            imageCount: previous?.imageCount ?? 0,
            installedBytes: previous?.installedBytes ?? 0,
            installedAt: previous?.installedAt
        )
        await perform {
            let client = try requireClient()
            value.gachaResourceStatus = try await client.post(
                "/v1/gacha-resources/install",
                body: GachaResourceInstallRequest(),
                timeout: 3_600
            )
            value.gachaEvents = try await client.get("/v1/gacha-events")
            if activeWishUID != nil { try await reloadWishes(client: client) }
            if let uid = selectedRole?.uid {
                let generation = companionDataGeneration
                let loaded: [GameCharacter] = try await client.post(
                    "/v1/characters/cache-assets",
                    body: GachaResourceInstallRequest(),
                    timeout: 3_600
                )
                if isCurrentCompanionData(uid: uid, generation: generation) {
                    characters = loaded
                }
            }
            await refreshGachaHistoryPresentation()
        }
        if value.gachaResourceStatus?.state == "installing" {
            value.gachaResourceStatus = previous
        }
    }

    func loginCloud() async {
        await perform {
            let result: CloudLoginResult = try await requireClient().post(
                "/v1/cloud/login/account",
                body: CredentialRequest(credential: try requireCredential())
            )
            try keychain.save(result.token, account: cloudKeychainAccount(uid: result.uid))
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
            let response: CountResponse = try await requireClient().post(
                "/v1/cloud/wishes/upload",
                body: CloudUIDRequest(uid: uid, token: try cloudToken(uid: uid))
            )
            value.cloudMessage = "已上传 \(response.uploaded ?? 0) 条记录"
        }
    }

    func retrieveCloudWishes() async {
        guard let uid = selectedRole?.uid else { return }
        guard value.cloudSession?.uid == uid else {
            message = "请先登录当前角色的云同步服务"
            return
        }
        await perform {
            let response: CountResponse = try await requireClient().post(
                "/v1/cloud/wishes/retrieve",
                body: CloudUIDRequest(uid: uid, token: try cloudToken(uid: uid))
            )
            await loadCompanionData()
            value.cloudMessage = "已取回 \(response.imported ?? 0) 条记录"
        }
    }

    func updateNotificationSettings(
        _ settings: NotificationSettings,
        revertingTo previous: NotificationSettings
    ) async {
        do {
            let saved: NotificationSettings = try await requireClient().put(
                "/v1/notifications/settings", body: settings
            )
            guard value.notificationSettings == settings else { return }
            value.notificationSettings = saved
            value.notificationError = nil
        } catch {
            guard value.notificationSettings == settings else { return }
            value.notificationSettings = previous
            value.notificationError = Self.presentableMessage(error)
        }
    }

    func evaluateNotifications() async {
        guard let uid = selectedRole?.uid else { return }
        do {
            let events: [NotificationEvent] = try await requireClient().post("/v1/notifications/evaluate?uid=\(uid)")
            value.notificationEvents = events
            try await UserNotificationService().deliver(events)
        } catch {
            message = Self.presentableMessage(error)
        }
    }

    func cloudKeychainAccount(uid: String) -> String { "cloud:\(uid)" }

    func cloudToken(uid: String) throws -> String {
        guard let token = try keychain.read(account: cloudKeychainAccount(uid: uid)) else {
            throw LauncherError.credentialMissing
        }
        return token
    }

}
