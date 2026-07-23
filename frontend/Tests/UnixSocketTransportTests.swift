import Darwin
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

    @Test("拒绝重复长度头和超出声明长度的响应")
    func ambiguousLength() {
        let duplicate = Data(
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\nok".utf8
        )
        let overlong = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nokay".utf8)
        #expect(throws: Error.self) {
            _ = try UnixSocketTransport.parseResponse(duplicate)
        }
        #expect(throws: Error.self) {
            _ = try UnixSocketTransport.parseResponse(overlong)
        }
    }

    @Test("生成短 Socket 路径")
    func shortPath() {
        #expect(BackendProcess.makeSocketPath().utf8.count < 104)
    }

    @Test("Socket 禁止 SIGPIPE")
    func noSignalPipe() throws {
        let descriptor = try UnixSocketTransport.makeConfiguredSocket()
        defer { Darwin.close(descriptor) }
        var value: Int32 = 0
        var length = socklen_t(MemoryLayout.size(ofValue: value))
        #expect(getsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &value, &length) == 0)
        #expect(value == 1)
    }

    @Test("等待 ready 可取消且有期限")
    func cancellableReadyWait() async throws {
        let pipe = Pipe(), drain = ProcessPipeDrain(handle: pipe.fileHandleForReading, capturesReady: true)
        let cancelled = Task { try await drain.readyPath(timeout: .seconds(5)) }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        let timeoutPipe = Pipe(), timeoutDrain = ProcessPipeDrain(handle: timeoutPipe.fileHandleForReading, capturesReady: true)
        let timed = Task { try await timeoutDrain.readyPath(timeout: .milliseconds(20)) }
        await #expect(throws: URLError.self) { _ = try await timed.value }
        drain.close(); timeoutDrain.close(); try pipe.fileHandleForWriting.close(); try timeoutPipe.fileHandleForWriting.close()
    }
}
