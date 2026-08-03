import AppKit
import Foundation

extension LauncherStore {
    func refreshGame() async {
        gameStateIntent += 1
        let intent = gameStateIntent
        await perform {
            let client = try requireClient()
            let path = installPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let state = try await client.game.status(path.isEmpty ? nil : path)
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
            speedLimitKB = try await client.game.speedLimit()
        }
    }

    func setSpeedLimit(_ kb: Int) async {
        await perform {
            let client = try requireClient()
            speedLimitKB = try await client.game.setSpeedLimit(kb)
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
            let request = StartGameLaunchRequest(
                installPath: installPath,
                performanceProfile: gamePerformanceProfile,
                metalHud: metalHudEnabled,
                networkDebug: networkDebugEnabled,
                wineLog: wineLogEnabled,
                framePacing: Self.preferredFrameRate(for: NSScreen.main?.maximumFramesPerSecond ?? 0),
                launchArguments: gameLaunchArguments
            )
            let launch = try await client.game.launch(request)
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
            let updated = try await client.game.stopLaunch(launch.id)
            guard gameLaunch?.id == launch.id else { return }
            applyGameLaunch(updated)
        }
    }

    nonisolated static func preferredFrameRate(for maximum: Int) -> Int {
        guard maximum >= 60 else { return 0 }
        return maximum % 60 == 0 ? maximum : 0
    }

    private func pollLaunch(_ id: String, intent: Int, client: LauncherClient) async {
        do {
            let events = client.game.launchEvents(id, gameLaunch?.revision)
            for try await launch in events {
                guard gameLaunchIntent == intent, gameLaunch?.id == id else { return }
                applyGameLaunch(launch)
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
