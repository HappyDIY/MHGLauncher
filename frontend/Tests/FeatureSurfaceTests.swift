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
}
