import Foundation

enum CoreLauncherClient {
    static func make(
        accounts: CoreAccountService,
        game: CoreGameService,
        launches: CoreGameLaunchService,
        wishes: CoreWishService,
        wishTasks: WishTaskCoordinator,
        notes: CoreNoteService,
        characters: CoreCharacterService,
        resources: CoreResourceService,
        achievements: CoreAchievementService,
        cloud: CoreCloudService,
        notifications: CoreNotificationService,
        updates: CoreUpdateService,
        images: CoreImageService
    ) -> LauncherClient {
        LauncherClient(
            accounts: AccountClient(
                list: { try await accounts.list() },
                selected: { try await accounts.selected() },
                roles: { try await accounts.roles() },
                createQRSession: { try await accounts.createQRSession() },
                queryQRSession: { try await accounts.queryQRSession($0) },
                sendMobileCaptcha: { try await accounts.sendMobileCaptcha($0) },
                verifyMobileCaptcha: { try await accounts.verifyMobileCaptcha($0) },
                prepareMobileLogin: { try await accounts.prepareMobileLogin($0) },
                prepareCookieLogin: { try await accounts.prepareCookieLogin($0) },
                commitLogin: { try await accounts.commit($0) },
                abortLogin: { await accounts.abort($0) },
                logout: { try await accounts.logout() },
                selectAccount: { try await accounts.selectAccount($0) },
                selectRole: { try await accounts.selectRole($0) }
            ),
            game: GameClient(
                status: { try await game.state(installPath: $0) },
                spaceCheck: { try await game.spaceCheck(path: $0, kind: $1) },
                startJob: { try await game.start(kind: $0, installPath: $1) },
                jobEvents: { id, revision in
                    AsyncThrowingStream { continuation in
                        Task {
                            let stream = await game.events(id, after: revision)
                            do {
                                for try await value in stream { continuation.yield(value) }
                                continuation.finish()
                            } catch { continuation.finish(throwing: error) }
                        }
                    }
                },
                controlJob: { try await game.control($0, action: $1) },
                speedLimit: { await game.speedLimit() },
                setSpeedLimit: { try await game.setSpeedLimit($0) },
                launch: { try await launches.start($0) },
                launchEvents: { launches.events($0, after: $1) },
                stopLaunch: { try await launches.stop($0) },
                runWineTool: { try await launches.runWineTool($0) }
            ),
            companion: CompanionClient(
                snapshot: { try await wishes.snapshot(uid: $0) },
                startWishSync: {
                    await wishTasks.start(kind: "sync") { log in
                        let inserted = try await wishes.sync { await log($0, false) }
                        return (["inserted": inserted], nil)
                    }
                },
                importUIGF: { data in
                    await wishTasks.start(kind: "import_uigf") { log in
                        let result = try await wishes.importUIGF(data)
                        await log("已校验并导入 UIGF 记录", true)
                        return (["imported": result.inserted, "uid_count": result.uids.count], result.uids)
                    }
                },
                importGachaURL: { value in
                    await wishTasks.start(kind: "import_gacha_url") { log in
                        let result = try await wishes.importGachaURL(value)
                        await log("抽卡 URL 导入完成", true)
                        return (["inserted": result.inserted, "uid_count": result.uids.count], result.uids)
                    }
                },
                wishTaskEvents: { wishTasks.events(id: $0, after: $1) },
                exportUIGF: { try await wishes.exportUIGF(uid: $0) },
                clearWishes: { try await wishes.clear() },
                refreshNote: {
                    try await notes.refresh(challenge: $0.xrpcChallenge, challengePath: $0.xrpcChallengePath)
                },
                verifyNote: {
                    NoteVerificationResponse(xrpcChallenge: try await notes.verify(
                        challenge: $0.challenge,
                        validate: $0.validate,
                        challengePath: $0.xrpcChallengePath
                    ))
                },
                characters: { try await characters.list(uid: $0) },
                refreshCharacters: { try await characters.refresh() },
                refreshCharacter: { try await characters.refreshDetail(avatarID: $0) },
                cacheCharacterAssets: {
                    guard let role = try await accounts.selectedRole() else { return [] }
                    return try await characters.list(uid: role.uid)
                }
            ),
            resources: ResourceClient(
                status: { await resources.status() },
                sync: { try await resources.sync(force: $0) },
                gachaStatus: { try await resources.gachaStatus() },
                gachaEvents: { try await resources.gachaEvents() }
            ),
            achievements: AchievementClient(
                archive: { try await achievements.archive(uid: $0) },
                snapshot: { try await achievements.snapshot(archiveID: $0) },
                goals: { try await achievements.goals() },
                importUIAF: { try await achievements.importUIAF(data: $0, archiveID: $1, expectedRevision: $2) },
                exportUIAF: { try await achievements.exportUIAF(archiveID: $0) },
                save: { try await achievements.save($0) }
            ),
            cloud: CloudClient(
                session: { try await cloud.session(uid: $0) },
                login: { try await cloud.login() },
                uploadWishes: { try await cloud.uploadWishes(uid: $0) },
                retrieveWishes: { try await cloud.retrieveWishes(uid: $0) },
                uploadAchievements: { try await cloud.uploadAchievements(uid: $0) },
                retrieveAchievements: { try await cloud.retrieveAchievements(uid: $0) }
            ),
            notifications: NotificationClient(
                settings: { try await notifications.settings() },
                updateSettings: { try await notifications.update($0) },
                evaluate: { try await notifications.evaluate(uid: $0) },
                acknowledge: { try await notifications.acknowledge($0) }
            ),
            updates: UpdateClient(manifest: { try await updates.manifest() }),
            images: ImageClient(load: { try await images.load($0) })
        )
    }

}
