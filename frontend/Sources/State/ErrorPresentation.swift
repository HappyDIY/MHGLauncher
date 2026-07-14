import Foundation

extension LauncherStore {
    nonisolated static func presentableMessage(_ error: APIErrorPayload) -> String {
        switch error.code {
        case "internal_error": "本地服务发生异常，请稍后重试"
        case "mihoyo_error", "mihoyo_response_invalid": "米游社请求失败，请稍后重试"
        case "cloud_error": "云同步服务暂不可用，请稍后重试"
        default: presentableMessage(error.message)
        }
    }

    // 按错误类型识别解码异常，避免依赖随 macOS 版本变化的本地化描述（如"数据丢失"）。
    nonisolated static func presentableMessage(_ error: Error) -> String {
        if error is DecodingError { return "本地数据格式异常，请刷新后重试" }
        return presentableMessage(error.localizedDescription)
    }

    nonisolated static func presentableMessage(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsChinese = normalized.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let unsafeTokens = ["\n", "/", "Error", "HTTP", "SQLITE", "ECONN"]
        guard !normalized.isEmpty, !normalized.allSatisfy(\.isNumber), normalized.count <= 120,
              containsChinese, !unsafeTokens.contains(where: normalized.contains) else {
            return "操作失败，请稍后重试"
        }
        return normalized
    }
}
