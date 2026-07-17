import Foundation
@testable import MHGLauncher

enum InteractiveFixtures {
    static let account = Account(
        aid: "1001", mid: "mid", nickname: "旅行者",
        credentialRef: "keychain:account:1001", selected: true, updatedAt: .now
    )
    static let role = GameRole(
        uid: "100000001", nickname: "荧", region: "cn_gf01",
        level: 60, selected: true
    )
    static let gameState = GameState(
        installPath: "/Games/Genshin Impact Game",
        installedVersion: "6.6.0",
        availableVersion: "6.7.0",
        status: .ready,
        updateKind: "full",
        downloadBytes: 1_048_576,
        predownloadVersion: "6.7.0",
        predownloadFinished: false
    )
    static let gameJob = GameJob(
        id: "job-1",
        kind: .predownload,
        status: .running,
        completedBytes: 512,
        totalBytes: 1024,
        message: "",
        downloadSpeed: 128,
        chunksCompleted: 1,
        chunksTotal: 2,
        activeChunks: [ChunkProgress(name: "pkg_001", bytesDone: 256, total: 512)],
        lastUpdate: "2026-07-06T00:00:00Z",
        revision: 1
    )
    static let gameLaunch = GameLaunch(
        id: "launch-1",
        status: .running,
        message: "游戏窗口已连接",
        performanceProfile: .optimized,
        metalHud: true,
        networkDebug: false,
        wineLog: false,
        progress: 0.9,
        logs: [GameLaunchLog(
            sequence: 1,
            timestamp: "2026-07-06T00:00:00Z",
            kind: "wine",
            message: "Wine 会话已启动"
        )],
        startedAt: "2026-07-06T00:00:00Z",
        updatedAt: "2026-07-06T00:00:01Z",
        revision: 1
    )
    static let dailyNote = DailyNote(
        uid: "100000001",
        currentResin: 120,
        maxResin: 200,
        finishedTasks: 4,
        totalTasks: 4,
        expeditionsFinished: 3,
        expeditionsTotal: 5,
        currentHomeCoin: 1800,
        maxHomeCoin: 2400,
        weeklyBossRemaining: 2,
        transformerReady: true,
        refreshedAt: .now
    )
    static let wishRecords = [
        WishRecord(
            id: "1", uid: "100000001", gachaType: "301",
            itemId: "10000089", name: "芙宁娜", itemType: "角色",
            rank: 5, time: .now, iconUrl: nil
        ),
        WishRecord(
            id: "2", uid: "100000001", gachaType: "301",
            itemId: "11401", name: "西风剑", itemType: "武器",
            rank: 4, time: .now.addingTimeInterval(-3600), iconUrl: nil
        )
    ]
    static let gachaEvent = GachaEvent(
        id: "event-1", version: "6.7", gachaType: "301", name: "镜中的茶宴",
        startedAt: .now.addingTimeInterval(-86_400),
        endedAt: .now.addingTimeInterval(86_400),
        orangeUp: ["芙宁娜"], purpleUp: ["西风剑"], bannerUrl: nil,
        updatedAt: .now
    )
    static let wishStatistics = WishStatistics(
        uid: "100000001",
        gachaType: "301",
        total: 2,
        fiveStarCount: 1,
        pullsSinceFiveStar: 1
    )
    static let bannerDetail = WishBannerDetail(
        uid: "100000001",
        gachaType: "301",
        total: 2,
        timeFrom: nil,
        timeTo: nil,
        fiveStarCount: 1,
        fourStarCount: 1,
        threeStarCount: 0,
        fiveStarPercent: 0.5,
        fourStarPercent: 0.5,
        threeStarPercent: 0,
        maxPity: 1,
        minPity: 1,
        averagePity: 1,
        lastPity: 1,
        lastPurplePity: 1,
        guaranteeThreshold: 80,
        fiveStarItems: [],
        fourStarItems: [],
        averageUpPity: 1,
        smallGuaranteeWinRate: 1
    )
}
