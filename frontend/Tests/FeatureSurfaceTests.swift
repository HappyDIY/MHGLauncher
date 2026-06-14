import SwiftUI
import Testing
@testable import MHGLauncher

@Suite("功能界面")
struct FeatureSurfaceTests {
    @Test("导航仅包含约定的五个入口")
    func destinations() {
        #expect(Destination.allCases.map(\.rawValue) == [
            "主页",
            "游戏",
            "祈愿记录",
            "实时便笺",
            "账号"
        ])
    }

    @Test("调试模式仅由明确环境变量开启")
    func debugMode() {
        #expect(HomeView.isDebugMode(environment: ["MHG_DEBUG_MODE": "1"]))
        #expect(!HomeView.isDebugMode(environment: [:]))
        #expect(!HomeView.isDebugMode(environment: ["MHG_DEBUG_MODE": "0"]))
    }

    @Test("旧版 UIGF 使用官方升级工具")
    @MainActor
    func uigfUpgrader() {
        #expect(WishesView.uigfUpgraderURL.absoluteString == "https://upgrader.uigf.org/")
    }

    @Test("祈愿页面统一角色活动卡池类型")
    func normalizedWishType() {
        let record = WishRecord(
            id: "1",
            uid: "100000001",
            gachaType: "400",
            itemId: "10000079",
            name: "芙宁娜",
            itemType: "角色",
            rank: 5,
            time: .now,
            iconUrl: nil
        )
        #expect(record.normalizedGachaType == "301")
    }

    @Test("卡池展示名称面向用户")
    func wishPoolPresentation() {
        let detail = WishBannerDetail(
            uid: "100000001",
            gachaType: "302",
            total: 10,
            timeFrom: nil,
            timeTo: nil,
            fiveStarCount: 0,
            fourStarCount: 1,
            threeStarCount: 9,
            fiveStarPercent: 0,
            fourStarPercent: 0.1,
            threeStarPercent: 0.9,
            maxPity: 0,
            minPity: 0,
            averagePity: 0,
            lastPity: 10,
            lastPurplePity: 0,
            guaranteeThreshold: 80,
            fiveStarItems: [],
            fourStarItems: []
        )
        #expect(detail.poolName == "武器活动祈愿")
        #expect(detail.poolIcon == "shield.lefthalf.filled")
    }

    @Test("二维码可以生成为非空图像")
    func qrCode() throws {
        let image = try #require(
            QRCodeImage.make("https://example.invalid/login?ticket=test")
        )
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test("实时便笺完整解码")
    func dailyNote() throws {
        let data = Data(
            """
            {
              "uid": "100000001",
              "current_resin": 120,
              "max_resin": 200,
              "finished_tasks": 3,
              "total_tasks": 4,
              "expeditions_finished": 2,
              "expeditions_total": 5,
              "current_home_coin": 1800,
              "max_home_coin": 2400,
              "weekly_boss_remaining": 2,
              "transformer_ready": true,
              "refreshed_at": "2026-06-11T08:00:00Z"
            }
            """.utf8
        )
        let note = try JSONDecoder.api.decode(DailyNote.self, from: data)
        #expect(note.currentResin == 120)
        #expect(note.transformerReady)
    }

    @Test("Keychain 凭据可写入读取并删除")
    func keychainRoundTrip() throws {
        let store = KeychainStore()
        let account = "test-\(UUID().uuidString)"
        defer { try? store.delete(account: account) }

        try store.save("stoken=test-secret", account: account)
        #expect(try store.read(account: account) == "stoken=test-secret")
        try store.delete(account: account)
        #expect(try store.read(account: account) == nil)
    }

    @Test("后端端口握手支持分段输出")
    func splitBackendReadyFrame() async throws {
        let pipe = Pipe()
        let writer = pipe.fileHandleForWriting

        Task.detached {
            writer.write(Data(#"{"event":"rea"#.utf8))
            try await Task.sleep(for: .milliseconds(10))
            writer.write(Data(#"dy","port":54321}"#.utf8))
            writer.write(Data([0x0A]))
        }

        let port = try await BackendProcess.readPort(
            from: pipe.fileHandleForReading
        )
        #expect(port == 54_321)
        try writer.close()
    }
}
