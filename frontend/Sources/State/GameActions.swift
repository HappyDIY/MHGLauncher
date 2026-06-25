import AppKit
import Foundation

extension LauncherStore {
    func refreshGame() async {
        await perform {
            let client = try requireClient()
            let path = installPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let state: GameState
            if path.isEmpty {
                state = try await client.get("/v1/game/status")
            } else {
                state = try await client.get(
                    "/v1/game/status/path",
                    query: [URLQueryItem(name: "install_path", value: path)]
                )
            }
            gameState = state
            if path.isEmpty || state.status != .notInstalled {
                installPath = state.installPath
            }
        }
    }

    func startGameJob(_ kind: JobKind) async {
        guard pendingGameJobKind == nil else { return }
        pendingGameJobKind = kind
        gameJob = nil
        defer { pendingGameJobKind = nil }
        await perform {
            guard !installPath.isEmpty else {
                message = "请先选择安装目录"
                return
            }
            let client = try requireClient()
            let request = StartJobRequest(kind: kind, installPath: installPath)
            let job: GameJob = try await client.post("/v1/game/jobs", body: request)
            gameJob = job
            pendingGameJobKind = nil
            try await pollJob(job.id, client: client)
        }
    }

    func controlGameJob(_ action: String) async {
        await perform {
            guard let job = gameJob else { return }
            let client = try requireClient()
            let request = ControlJobRequest(action: action)
            let updated: GameJob = try await client.post(
                "/v1/game/jobs/\(job.id)/control",
                body: request
            )
            gameJob = updated
        }
    }

    func launchGame() async {
        guard !isLaunchingGame else { return }
        if account == nil, UserDefaults.standard.integer(forKey: loginDeferralKey) < 2 {
            showsLoginBeforeLaunch = true
            return
        }
        await startLaunch()
    }

    func deferLoginAndLaunch() async {
        let count = UserDefaults.standard.integer(forKey: loginDeferralKey)
        UserDefaults.standard.set(count + 1, forKey: loginDeferralKey)
        showsLoginBeforeLaunch = false
        await startLaunch()
    }

    private func startLaunch() async {
        isLaunchingGame = true
        defer { isLaunchingGame = false }
        await perform {
            guard !installPath.isEmpty else {
                message = "请先选择安装目录"
                return
            }
            let client = try requireClient()
            let launchCredential = try requireLaunchCredential()
            let request = StartGameLaunchRequest(
                installPath: installPath,
                performanceProfile: gamePerformanceProfile,
                metalHud: metalHudEnabled,
                networkDebug: networkDebugEnabled,
                framePacing: Self.preferredFrameRate(for: NSScreen.main?.maximumFramesPerSecond ?? 0),
                credential: launchCredential
            )
            let launch: GameLaunch = try await client.post("/v1/game/launch", body: request)
            gameLaunch = launch
            Task { await self.pollLaunch(launch.id, client: client) }
        }
    }

    func stopGame() async {
        guard let launch = gameLaunch, !isStoppingGame else { return }
        isStoppingGame = true
        defer { isStoppingGame = false }
        await perform {
            let client = try requireClient()
            let updated: GameLaunch = try await client.post("/v1/game/launches/\(launch.id)/stop")
            gameLaunch = updated
        }
    }

    nonisolated static func preferredFrameRate(for maximum: Int) -> Int {
        guard maximum >= 60 else { return 0 }
        return maximum % 60 == 0 ? maximum : 0
    }

    private func pollLaunch(_ id: String, client: APIClient) async {
        do {
            while !Task.isCancelled {
                let launch: GameLaunch = try await client.get("/v1/game/launches/\(id)")
                gameLaunch = launch
                if [.stopped, .exited, .failed].contains(launch.status) { return }
                try await Task.sleep(for: .milliseconds(200))
            }
        } catch {
            message = Self.presentableMessage(error.localizedDescription)
        }
    }

    private func pollJob(_ id: String, client: APIClient) async throws {
        while !Task.isCancelled {
            let job: GameJob = try await client.get("/v1/game/jobs/\(id)")
            gameJob = job
            if [.completed, .cancelled, .failed].contains(job.status) {
                await refreshGame()
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
    }
}

struct EmptyResponse: Codable {}
