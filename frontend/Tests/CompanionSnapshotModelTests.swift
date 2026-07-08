import Foundation
import Testing
@testable import MHGLauncher

@Suite("陪伴数据快照模型")
struct CompanionSnapshotModelTests {
    @Test("解码陪伴数据快照")
    func decodeCompanionSnapshot() throws {
        let data = Data(
            """
            {
              "wishes": [],
              "statistics": [{"uid":"100000001","gacha_type":"301","total":1,"five_star_count":1,"pulls_since_five_star":0}],
              "banner_statistics": [],
              "note": null
            }
            """.utf8
        )
        let snapshot = try JSONDecoder.api.decode(CompanionSnapshot.self, from: data)
        #expect(snapshot.statistics.first?.total == 1)
        #expect(snapshot.note == nil)
    }
}
