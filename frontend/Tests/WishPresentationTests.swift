import Foundation
import Testing
@testable import MHGLauncher

@Suite("祈愿展示数据")
struct WishPresentationTests {
    @Test("五星条目同时解码累计位置与单次保底")
    func decodesBannerItemPity() throws {
        let data = Data(
            """
            {
              "name": "芙宁娜",
              "item_id": "10000089",
              "item_type": "角色",
              "rank": 5,
              "icon_url": null,
              "pull_number": 2155,
              "pity": 27,
              "time": "2026-06-14T21:05:00"
            }
            """.utf8
        )

        let item = try JSONDecoder.api.decode(WishBannerItem.self, from: data)

        #expect(item.pullNumber == 2_155)
        #expect(item.pity == 27)
    }
}
