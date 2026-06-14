import Foundation
import Testing
@testable import MHGLauncher

@Suite("UIGF 文件读写")
struct UIGFFileIOTests {
    @Test("导出 JSON 使用稳定的可读格式")
    func formattedExport() throws {
        let source = Data(#"{"hk4e":[],"info":{"version":"v4.2"}}"#.utf8)
        let data = try UIGFFileIO.formattedJSON(source)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\n"))
        #expect(text.firstIndex(of: "h")! < text.firstIndex(of: "i")!)
    }

    @Test("拒绝将非 JSON 响应写入 UIGF 文件")
    func rejectsInvalidJSON() {
        #expect(throws: (any Error).self) {
            try UIGFFileIO.formattedJSON(Data("backend error".utf8))
        }
    }
}
