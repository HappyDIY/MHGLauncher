import Foundation

extension LauncherStore {
    func startGameJob(_ kind: JobKind) async {
        guard pendingGameJobKind == nil else { return }
        gameJobIntent += 1
        let intent = gameJobIntent
        pendingGameJobKind = kind
        gameJob = nil
        defer { pendingGameJobKind = nil }
        await perform {
            guard !installPath.isEmpty else {
                message = "请先选择安装目录"
                return
            }
            let client = try requireClient()
            let path = installPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let state = try await client.game.status(path.isEmpty ? nil : path)
            guard gameJobIntent == intent else { return }
            guard state.status != .notInstalled || kind == .install else {
                message = "所选目录中未检测到游戏客户端"
                return
            }
            guard kind != .predownload || state.canStartPredownload else {
                message = "请先完成常规更新或资源修复后再预下载"
                return
            }
            let spaceCheck = try await client.game.spaceCheck(state.installPath, kind)
            guard gameJobIntent == intent else { return }
            guard spaceCheck.sufficient else {
                let available = ByteCountFormatter.string(
                    fromByteCount: spaceCheck.available, countStyle: .file
                )
                let required = ByteCountFormatter.string(
                    fromByteCount: spaceCheck.required, countStyle: .file
                )
                message = "磁盘空间不足：需要 \(required)，可用 \(available)"
                return
            }
            let job = try await client.game.startJob(kind, state.installPath)
            guard gameJobIntent == intent else { return }
            gameJob = job
            pendingGameJobKind = nil
            try await pollJob(job.id, intent: intent, client: client)
        }
    }

    func controlGameJob(_ action: String) async {
        await perform {
            guard let job = gameJob else { return }
            let client = try requireClient()
            let updated = try await client.game.controlJob(job.id, action)
            guard gameJob?.id == job.id else { return }
            applyGameJob(updated)
        }
    }

    private func pollJob(_ id: String, intent: Int, client: LauncherClient) async throws {
        let scheduler = DisplayLinkFrameScheduler()
        let presenter = LatestDisplayFrameCoalescer<GameJob>(
            scheduler: scheduler
        ) { [weak self] job in
            self?.applyGameJob(job)
        }
        defer { presenter.cancel() }
        let events = client.game.jobEvents(id, gameJob?.revision)
        for try await job in events {
            guard gameJobIntent == intent, gameJob?.id == id else { return }
            presenter.submit(job)
            if [.completed, .cancelled, .failed].contains(job.status) {
                presenter.flush()
                await refreshGame()
                return
            }
        }
    }

    private func applyGameJob(_ value: GameJob) {
        let currentRevision = gameJob?.revision ?? 0
        guard gameJob?.id != value.id || (value.revision ?? 0) >= currentRevision else { return }
        gameJob = value
    }
}
