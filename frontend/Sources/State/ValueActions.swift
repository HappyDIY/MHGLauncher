import Foundation

extension LauncherStore {
    func loadValueData() async {
        guard let uid = selectedRole?.uid else { return }
        do {
            let client = try requireClient()
            async let events: [GachaEvent] = client.get("/v1/gacha-events")
            async let loadedCharacters: [GameCharacter] = client.get(
                "/v1/characters", query: [URLQueryItem(name: "uid", value: uid)]
            )
            async let settings: NotificationSettings = client.get("/v1/notifications/settings")
            async let goals: [AchievementGoal] = client.get("/v1/achievements/goals")
            do {
                try await loadAchievementData(client: client)
                value.achievementGoals = try await goals
                value.achievementLoaded = true
                value.achievementError = nil
            } catch {
                value.achievementError = Self.presentableMessage(error)
            }
            do { value.gachaEvents = try await events } catch { message = Self.presentableMessage(error) }
            do {
                characters = try await loadedCharacters
                if selectedCharacterId == nil
                    || !characters.contains(where: { $0.avatarId == selectedCharacterId }) {
                    selectedCharacterId = characters.first?.avatarId
                }
            } catch { message = Self.presentableMessage(error) }
            do {
                value.notificationSettings = try await settings
                value.notificationError = nil
            } catch {
                value.notificationError = Self.presentableMessage(error)
            }
        } catch {
            value.achievementError = Self.presentableMessage(error)
            value.notificationError = value.achievementError
        }
    }

    func refreshGachaEvents() async {
        await perform {
            value.gachaEvents = try await requireClient().post(
                "/v1/gacha-events/refresh",
                body: CredentialRequest(credential: try requireCredential())
            )
        }
    }

    func loginCloud() async {
        await perform {
            let result: CloudLoginResult = try await requireClient().post(
                "/v1/cloud/login",
                body: GachaURLRequest(gachaUrl: value.cloudLoginURL, token: nil)
            )
            try keychain.save(result.token, account: cloudKeychainAccount(uid: result.uid))
            value.cloudSession = CloudSession(uid: result.uid, tokenRef: result.tokenRef, reverifiedAt: result.reverifiedAt, updatedAt: result.reverifiedAt)
            value.cloudMessage = "已登录 UID \(result.uid)"
        }
    }

    func uploadCloudWishes() async {
        guard let uid = selectedRole?.uid else { return }
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
        await perform {
            let response: CountResponse = try await requireClient().post(
                "/v1/cloud/wishes/retrieve",
                body: CloudUIDRequest(uid: uid, token: try cloudToken(uid: uid))
            )
            await loadCompanionData()
            value.cloudMessage = "已取回 \(response.imported ?? 0) 条记录"
        }
    }

    func updateNotificationSettings(_ settings: NotificationSettings) async {
        await perform {
            value.notificationSettings = try await requireClient().put("/v1/notifications/settings", body: settings)
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
