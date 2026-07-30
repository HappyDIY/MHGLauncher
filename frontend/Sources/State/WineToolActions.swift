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
        }
    }
}
