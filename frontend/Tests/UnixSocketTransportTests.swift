import Foundation
import Testing
@testable import MHGLauncher

@Suite("Unix Socket HTTP")
struct UnixSocketTransportTests {
    @Test("解析 Content-Length 响应")
    func contentLength() throws {
        let data = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok".utf8)
        let response = try UnixSocketTransport.parseResponse(data)
        #expect(response.status == 200)
        #expect(String(data: response.body, encoding: .utf8) == "ok")
    }

    @Test("解析 chunked 响应")
    func chunked() throws {
        let data = Data("""
        HTTP/1.1 200 OK\r
        Transfer-Encoding: chunked\r
        \r
        4\r
        test\r
        3\r
        ing\r
        0\r
        \r

        """.utf8)
        let response = try UnixSocketTransport.parseResponse(data)
        #expect(String(data: response.body, encoding: .utf8) == "testing")
    }

    @Test("拒绝截断响应")
    func truncated() {
        let data = Data("HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nshort".utf8)
        #expect(throws: Error.self) {
            _ = try UnixSocketTransport.parseResponse(data)
        }
    }

    @Test("生成短 Socket 路径")
    func shortPath() {
        #expect(BackendProcess.makeSocketPath().utf8.count < 104)
    }
}
