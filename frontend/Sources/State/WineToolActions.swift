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
            try await client.game.runWineTool(request)
            showStatus(action.successMessage)
        }
    }
}

extension WineToolAction {
    var successMessage: String {
        switch self {
        case .explorer: "已打开 Wine 文件目录"
        case .preferences: "已启动 Wine 首选项"
        case .run: "已运行 Windows 命令"
        }
    }
}
