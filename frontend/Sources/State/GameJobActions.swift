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
            let checkPath = path.isEmpty ? "/v1/game/status" : "/v1/game/status/path"
            let query = path.isEmpty ? [] : [URLQueryItem(name: "install_path", value: path)]
            let state: GameState = try await client.get(checkPath, query: query)
            guard gameJobIntent == intent else { return }
            guard state.status != .notInstalled || kind == .install else {
                message = "所选目录中未检测到游戏客户端"
                return
            }
            guard kind != .predownload || state.canStartPredownload else {
                message = "请先完成常规更新或资源修复后再预下载"
                return
            }
            let spaceCheck: SpaceCheckResult = try await client.get(
                "/v1/game/space-check",
                query: [
                    URLQueryItem(name: "install_path", value: state.installPath),
                    URLQueryItem(name: "kind", value: kind.rawValue)
                ]
            )
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
            let request = StartJobRequest(kind: kind, installPath: state.installPath)
            let job: GameJob = try await client.post("/v1/game/jobs", body: request)
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
            let request = ControlJobRequest(action: action)
            let updated: GameJob = try await client.post(
                "/v1/game/jobs/\(job.id)/control", body: request
            )
            guard gameJob?.id == job.id else { return }
            applyGameJob(updated)
        }
    }

    private func pollJob(_ id: String, intent: Int, client: APIClient) async throws {
        var revision = gameJob?.revision
        while !Task.isCancelled {
            let job: GameJob = try await client.get(
                "/v1/game/jobs/\(id)", query: LongPollQuery.items(after: revision)
            )
            guard gameJobIntent == intent, gameJob?.id == id else { return }
            applyGameJob(job)
            revision = job.revision
            if [.completed, .cancelled, .failed].contains(job.status) {
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
