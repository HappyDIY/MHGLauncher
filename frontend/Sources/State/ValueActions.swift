import Foundation

extension LauncherStore {
    func loadValueData() async {
        guard let uid = selectedRole?.uid else { return }
        await perform {
            let client = try requireClient()
            async let events: [GachaEvent] = client.get("/v1/gacha-events")
            async let characters: [GameCharacter] = client.get("/v1/characters", query: [URLQueryItem(name: "uid", value: uid)])
            async let settings: NotificationSettings = client.get("/v1/notifications/settings")
            async let archives: [AchievementArchive] = client.get("/v1/achievements/archives")
            value.gachaEvents = try await events
            value.characters = try await characters
            value.notificationSettings = try await settings
            value.achievementArchives = try await archives
            try await loadAchievements(client: client)
        }
    }

    func refreshCharacters() async {
        await perform {
            value.characters = try await requireClient().post(
                "/v1/characters/refresh",
                body: CredentialRequest(credential: try requireCredential())
            )
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

    func loadCycle(_ kind: CycleKind) async {
        guard let uid = selectedRole?.uid else { return }
        await perform {
            value.cycles[kind] = try await requireClient().get(
                "/v1/cycles/\(kind.rawValue)",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
        }
    }

    func refreshCycle(_ kind: CycleKind) async {
        await perform {
            value.cycles[kind] = try await requireClient().post(
                "/v1/cycles/\(kind.rawValue)/refresh",
                body: CredentialRequest(credential: try requireCredential())
            )
        }
    }

    func uploadCycle(_ record: CycleRecord) async {
        await perform {
            let token = try cloudToken(uid: record.uid)
            let body = CloudCycleUploadRequest(uid: record.uid, token: token, scheduleId: record.scheduleId)
            _ = try await requireClient().post("/v1/cycles/\(record.kind.rawValue)/upload", body: body) as CountResponse
            await loadCycle(record.kind)
        }
    }

    func createAchievementArchive() async {
        await perform {
            let name = "成就档案 \(value.achievementArchives.count + 1)"
            _ = try await requireClient().post("/v1/achievements/archives", body: AchievementArchiveRequest(name: name)) as AchievementArchive
            try await loadAchievements(client: requireClient())
        }
    }

    func saveAchievementDraft() async {
        guard let archiveId = value.achievementArchives.first(where: \.selected)?.id,
              let id = Int(value.achievementDraftId) else { return }
        await perform {
            let item = AchievementItemInput(
                achievementId: id,
                current: value.achievementDraftCurrent,
                status: value.achievementDraftStatus,
                timestamp: Int(Date().timeIntervalSince1970)
            )
            value.achievements = try await requireClient().post(
                "/v1/achievements",
                body: AchievementSaveRequest(archiveId: archiveId, items: [item])
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
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    func cloudKeychainAccount(uid: String) -> String { "cloud:\(uid)" }
    func cloudToken(uid: String) throws -> String {
        guard let token = try keychain.read(account: cloudKeychainAccount(uid: uid)) else {
            throw LauncherError.credentialMissing
        }
        return token
    }

    private func loadAchievements(client: APIClient) async throws {
        value.achievementArchives = try await client.get("/v1/achievements/archives")
        value.achievements = try await client.get("/v1/achievements")
    }
}
