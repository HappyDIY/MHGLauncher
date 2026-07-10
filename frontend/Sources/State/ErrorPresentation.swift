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

    nonisolated static func presentableMessage(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "未能读取数据，因为它的格式不正确。" {
            return "本地数据格式异常，请刷新后重试"
        }
        let containsChinese = normalized.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let unsafeTokens = ["\n", "/", "Error", "HTTP", "SQLITE", "ECONN"]
        guard !normalized.isEmpty, !normalized.allSatisfy(\.isNumber), normalized.count <= 120,
              containsChinese, !unsafeTokens.contains(where: normalized.contains) else {
            return "操作失败，请稍后重试"
        }
        return normalized
    }
}
