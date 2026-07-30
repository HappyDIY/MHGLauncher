import Foundation

extension LauncherStore {
    func startWineTool(_ action: WineToolAction, command: String? = nil) async {
        guard !isStartingWineTool else { return }
        isStartingWineTool = true
        defer { isStartingWineTool = false }
        await perform {
            try await ensureGameRuntime()
            let client = try requireClient()
            let request = WineToolRequest(
                action: action,
                command: command,
                performanceProfile: gamePerformanceProfile
            )
            let _: EmptyResponse = try await client.post("/v1/game/wine-tools", body: request)
            showStatus(action.successMessage)
        }
    }
}

extension WineToolAction {
    var successMessage: String {
        switch self {
        case .explorer: "已打开 Wine 文件目录"
        case .preferences: "Wine 首选项已应用"
        case .run: "已运行 Windows 命令"
        }
    }
}
