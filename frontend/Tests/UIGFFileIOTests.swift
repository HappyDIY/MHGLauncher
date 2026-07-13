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

    @Test("导入在读取前拒绝超大文件")
    func rejectsOversizedImport() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(UIGFFileIO.maximumImportBytes + 1))
        try handle.close()
        #expect(throws: URLError.self) {
            _ = try UIGFFileIO.read(from: url)
        }
    }
}
