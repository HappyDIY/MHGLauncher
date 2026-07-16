import Foundation
import Testing
@testable import MHGLauncher

@Suite("运行时提升安全")
struct RuntimePromotionTests {
    @Test("伪造的提升记录不会删除已有文件")
    func unsafePromotionDoesNotDeleteFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "runtime-promotion-\(UUID().uuidString)")
        let parent = root.appending(path: "Runtimes")
        let outside = root.appending(path: "outside")
        let journal = parent.appending(path: ".v0.1.0.promotion.json")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("keep".utf8).write(to: outside.appending(path: "value"))
        let forged = RuntimePromotionRecord(
            schemaVersion: 1,
            stage: outside.path,
            destination: outside.path,
            backup: outside.appending(path: "backup").path,
            stageIdentity: RuntimeDirectoryIdentity(volume: 0, file: 0),
            destinationIdentity: nil
        )
        try JSONEncoder().encode(forged).write(to: journal)
        #expect(throws: RuntimeInstallError.unsafePromotion) {
            try RuntimePromotion.recover(journal: journal)
        }
        let value = try Data(contentsOf: outside.appending(path: "value"))
        #expect(String(decoding: value, as: UTF8.self) == "keep")
    }
}
