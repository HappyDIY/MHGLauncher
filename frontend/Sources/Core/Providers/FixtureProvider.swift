import Foundation

actor FixtureProvider: GameProvider {
    private var polls: [String: Int] = [:]

    func createQRSession() async throws -> QRSession {
        let session = makeSession(id: "fixture-ticket", status: "created")
        polls[session.id] = 0
        return session
    }

    func queryQRSession(_ id: String) async throws -> (QRSession, ProviderIdentity?) {
        let count = (polls[id] ?? 0) + 1
        polls[id] = count
        let session = makeSession(id: id, status: count >= 2 ? "confirmed" : "scanned")
        guard count >= 2 else { return (session, nil) }
        return (session, ProviderIdentity(
            aid: "10001",
            mid: "fixture-mid",
            nickname: "测试旅行者",
            credential: "stoken=fixture; mid=fixture-mid"
        ))
    }

    func identifyCredential(_ credential: String) async throws -> ProviderIdentity {
        let values = credential.split(separator: ";").reduce(into: [String: String]()) { result, item in
            let pair = item.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            if pair.count == 2 { result[String(pair[0])] = String(pair[1]) }
        }
        let aid = values["stuid"] ?? values["account_id"] ?? "10001"
        return ProviderIdentity(
            aid: aid,
            mid: values["mid"] ?? "fixture-mid-\(aid)",
            nickname: "测试旅行者",
            credential: credential
        )
    }

    func createMobileCaptcha(_ mobile: String) async throws -> MobileCaptchaSession {
        MobileCaptchaSession(
            mobile: mobile,
            actionType: "fixture-action",
            countdown: 60,
            aigis: nil,
            verification: nil
        )
    }

    func verifyMobileCaptcha(
        _ request: MobileCaptchaVerificationRequest
    ) async throws -> MobileCaptchaSession {
        MobileCaptchaSession(
            mobile: request.mobile,
            actionType: "fixture-action",
            countdown: 60,
            aigis: "fixture-aigis",
            verification: nil
        )
    }

    func loginByMobileCaptcha(_ request: MobileLoginRequest) async throws -> ProviderIdentity {
        ProviderIdentity(
            aid: "10001",
            mid: "fixture-mid",
            nickname: "手机用户\(request.mobile.suffix(4))",
            credential: "stoken=fixture; mid=fixture-mid"
        )
    }

    func roles(credential: String) async throws -> [GameRole] {
        [GameRole(
            uid: "100000001",
            nickname: "旅行者",
            region: "cn_gf01",
            level: 60,
            selected: true
        )]
    }

    func build(installedVersion: String, audioLanguages: [String]) async throws -> GameBuild {
        try SophonValidation.validate(GameBuild(
            version: "5.8.0",
            segments: [PackageSegment(
                url: URL(string: "https://example.invalid/game.zip")!,
                md5: String(repeating: "0", count: 32),
                size: 1,
                filename: "game.zip"
            )]
        ))
    }

    func installedBuild(version: String, audioLanguages: [String]) async throws -> GameBuild {
        var value = try await build(installedVersion: version, audioLanguages: audioLanguages)
        value = GameBuild(
            version: version,
            kind: value.kind,
            pendingBytes: value.pendingBytes,
            segments: value.segments,
            assets: value.assets,
            patchAssets: value.patchAssets,
            deprecatedFiles: value.deprecatedFiles,
            baseAssets: value.baseAssets,
            repairAssets: value.repairAssets,
            isPredownload: value.isPredownload
        )
        return value
    }

    func predownloadBuild(installedVersion: String, audioLanguages: [String]) async throws -> GameBuild? {
        try SophonValidation.validate(GameBuild(
            version: "5.9.0",
            segments: [PackageSegment(
                url: URL(string: "https://example.invalid/predownload.zip")!,
                md5: String(repeating: "0", count: 32),
                size: 1,
                filename: "predownload.zip"
            )],
            isPredownload: true
        ))
    }

    func gachaURL(credential: String, role: GameRole) async throws -> URL {
        var components = URLComponents(string: "https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog")!
        components.queryItems = [
            URLQueryItem(name: "auth_appid", value: "webview_gacha"),
            URLQueryItem(name: "authkey", value: "fixture"),
            URLQueryItem(name: "authkey_ver", value: "1"),
            URLQueryItem(name: "sign_type", value: "2"),
            URLQueryItem(name: "lang", value: "zh-cn"),
            URLQueryItem(name: "uid", value: role.uid)
        ]
        return components.url!
    }

    nonisolated func wishes(
        credential: String,
        role: GameRole,
        newest: [String: String]
    ) -> AsyncThrowingStream<[WishRecord], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([
                WishRecord(
                    id: "1002", uid: role.uid, gachaType: "301", itemId: "10000089",
                    name: "测试角色", itemType: "角色", rank: 5,
                    time: Self.date("2026-06-10T12:00:00+08:00"), iconUrl: nil
                ),
                WishRecord(
                    id: "1001", uid: role.uid, gachaType: "301", itemId: "15401",
                    name: "测试武器", itemType: "武器", rank: 3,
                    time: Self.date("2026-06-10T11:59:00+08:00"), iconUrl: nil
                )
            ])
            continuation.finish()
        }
    }

    nonisolated func wishes(gachaURL: URL) -> AsyncThrowingStream<[WishRecord], Error> {
        let uid = URLComponents(url: gachaURL, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "uid" })?.value ?? "100000001"
        return wishes(credential: "fixture", role: GameRole(
            uid: uid, nickname: "旅行者", region: "cn_gf01", level: 60, selected: true
        ), newest: [:])
    }

    func dailyNote(
        credential: String,
        role: GameRole,
        challenge: String,
        challengePath: String
    ) async throws -> DailyNote {
        DailyNote(
            uid: role.uid,
            currentResin: 120,
            maxResin: 200,
            finishedTasks: 3,
            totalTasks: 4,
            extraTaskRewardReceived: false,
            expeditionsFinished: 2,
            expeditionsTotal: 5,
            currentHomeCoin: 1800,
            maxHomeCoin: 2400,
            weeklyBossRemaining: 2,
            transformerReady: true,
            refreshedAt: Self.date("2026-06-11T08:00:00+08:00")
        )
    }

    func verifyNoteChallenge(
        credential: String,
        challenge: String,
        validate: String,
        challengePath: String
    ) async throws -> String {
        "fixture-xrpc-challenge"
    }

    func authTicket(credential: String) async throws -> String {
        "fixture-auth-ticket"
    }

    private func makeSession(id: String, status: String) -> QRSession {
        QRSession(
            id: id,
            url: "https://example.invalid/fixture-login",
            status: status,
            expiresAt: Date().addingTimeInterval(300)
        )
    }

    private nonisolated static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}
