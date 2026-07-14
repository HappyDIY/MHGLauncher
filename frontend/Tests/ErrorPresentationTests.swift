import Foundation
import Testing
@testable import MHGLauncher

@Suite("错误展示")
struct ErrorPresentationTests {
    @Test("内部错误不展示原始信息")
    func internalErrorIsGeneric() throws {
        #expect(LauncherStore.presentableMessage(try payload("internal_error", "SQLITE_ERROR: /private/data.db")) == "本地服务发生异常，请稍后重试")
    }

    @Test("上游错误不展示原始信息")
    func providerErrorIsGeneric() throws {
        #expect(LauncherStore.presentableMessage(try payload("mihoyo_error", "HTTP 500 upstream")) == "米游社请求失败，请稍后重试")
    }

    @Test("领域错误保留用户可读文案")
    func domainErrorIsRetained() {
        #expect(LauncherStore.presentableMessage("请先选择安装目录") == "请先选择安装目录")
    }

    @Test("数据解码错误使用可行动提示")
    func decodingErrorIsActionable() {
        // 用真实 DecodingError 验证按类型识别，不依赖随 macOS 版本变化的本地化描述。
        let error: Error
        do {
            struct Required: Decodable { let value: String }
            _ = try JSONDecoder().decode(Required.self, from: Data("{}".utf8))
            Issue.record("应抛出 DecodingError")
            return
        } catch let caught {
            error = caught
        }
        #expect(error is DecodingError)
        #expect(LauncherStore.presentableMessage(error) == "本地数据格式异常，请刷新后重试")
    }

    @Test("本地服务启动失败不展示系统错误")
    func backendStartupErrorIsGeneric() {
        #expect(BackendProcess.startupFailureMessage == "本地服务启动失败，请检查运行时安装后重试")
    }
}

private func payload(_ code: String, _ message: String) throws -> APIErrorPayload {
    try JSONDecoder.api.decode(APIErrorPayload.self, from: Data("{\"code\":\"\(code)\",\"message\":\"\(message)\",\"details\":{}}".utf8))
}
