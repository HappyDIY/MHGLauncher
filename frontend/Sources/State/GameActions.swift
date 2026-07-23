import AppKit
import Foundation

extension LauncherStore {
    func refreshGame() async {
        gameStateIntent += 1
        let intent = gameStateIntent
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
            guard gameStateIntent == intent else { return }
            gameState = state
            if path.isEmpty || state.status != .notInstalled {
                installPath = state.installPath
            }
        }
    }

    func refreshSpeedLimit() async {
        await perform {
            let client = try requireClient()
            let response: SpeedLimitResponse = try await client.get("/v1/settings/speed-limit")
            speedLimitKB = response.speedLimitKb
        }
    }

    func setSpeedLimit(_ kb: Int) async {
        await perform {
            let client = try requireClient()
            let request = SpeedLimitRequest(speedLimitKb: kb)
            let response: SpeedLimitResponse = try await client.post("/v1/settings/speed-limit", body: request)
            speedLimitKB = response.speedLimitKb
            userSettings.set(speedLimitKB, forKey: "downloadSpeedLimitKB")
        }
    }

    func launchGame() async {
        guard !isLaunchingGame else { return }
        if account == nil, userSettings.integer(forKey: loginDeferralKey) < 2 {
            showsLoginBeforeLaunch = true
            return
        }
        await startLaunch()
    }

    func deferLoginAndLaunch() async {
        let count = userSettings.integer(forKey: loginDeferralKey)
        userSettings.set(count + 1, forKey: loginDeferralKey)
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
            try await ensureGameRuntime()
            let client = try requireClient()
            let launchCredential = try requireLaunchCredential()
            let request = StartGameLaunchRequest(
                installPath: installPath,
                performanceProfile: gamePerformanceProfile,
                metalHud: metalHudEnabled,
                networkDebug: networkDebugEnabled,
                wineLog: wineLogEnabled,
                framePacing: Self.preferredFrameRate(for: NSScreen.main?.maximumFramesPerSecond ?? 0),
                credential: launchCredential
            )
            let launch: GameLaunch = try await client.post("/v1/game/launch", body: request)
            gameLaunchIntent += 1
            let intent = gameLaunchIntent
            launchPollingTask?.cancel()
            gameLaunch = launch
            launchPollingTask = Task { await self.pollLaunch(launch.id, intent: intent, client: client) }
        }
    }

    func stopGame() async {
        guard let launch = gameLaunch, !isStoppingGame else { return }
        isStoppingGame = true
        defer { isStoppingGame = false }
        await perform {
            let client = try requireClient()
            let updated: GameLaunch = try await client.post("/v1/game/launches/\(launch.id)/stop")
            guard gameLaunch?.id == launch.id else { return }
            applyGameLaunch(updated)
        }
    }

    nonisolated static func preferredFrameRate(for maximum: Int) -> Int {
        guard maximum >= 60 else { return 0 }
        return maximum % 60 == 0 ? maximum : 0
    }

    private func pollLaunch(_ id: String, intent: Int, client: APIClient) async {
        do {
            var revision = gameLaunch?.revision
            while !Task.isCancelled {
                let launch: GameLaunch = try await client.get(
                    "/v1/game/launches/\(id)",
                    query: LongPollQuery.items(after: revision)
                )
                guard gameLaunchIntent == intent, gameLaunch?.id == id else { return }
                applyGameLaunch(launch)
                revision = launch.revision
                if [.stopped, .exited, .failed].contains(launch.status) { return }
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard gameLaunchIntent == intent else { return }
            message = Self.presentableMessage(error)
        }
    }

    private func applyGameLaunch(_ value: GameLaunch) {
        guard gameLaunch?.id != value.id || (value.revision ?? 0) >= (gameLaunch?.revision ?? 0) else { return }
        gameLaunch = value
    }
}

struct EmptyResponse: Codable {}
