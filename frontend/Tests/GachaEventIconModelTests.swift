import Foundation
import Testing
@testable import MHGLauncher

@Suite("历史卡池图标模型")
struct GachaEventIconModelTests {
    @Test("解码后端提供的UP图标映射")
    func decodesUpIconURLs() throws {
        let data = Data(
            """
            {
              "id": "event",
              "version": "4.6",
              "gacha_type": "301",
              "name": "炉边烬影",
              "started_at": "2024-04-24T06:00:00+08:00",
              "ended_at": "2024-05-14T17:59:00+08:00",
              "orange_up": ["阿蕾奇诺"],
              "purple_up": [],
              "orange_up_icons": {
                "阿蕾奇诺": "/v1/gacha-resources/files/images/arlecchino.img"
              },
              "purple_up_icons": {},
              "banner_url": null,
              "updated_at": "2024-05-14T17:59:00+08:00"
            }
            """.utf8
        )

        let event = try JSONDecoder.api.decode(GachaEvent.self, from: data)

        #expect(
            event.orangeUpIcons?["阿蕾奇诺"]?.relativeString
                == "/v1/gacha-resources/files/images/arlecchino.img"
        )
    }
}
