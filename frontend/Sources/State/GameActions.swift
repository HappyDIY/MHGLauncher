import Foundation

extension LauncherStore {
    func refreshGame() async {
        await perform {
            let client = try requireClient()
            let state: GameState = try await client.get("/v1/game/status")
            gameState = state
            if installPath.isEmpty {
                installPath = state.installPath
            }
        }
    }

    func startGameJob(_ kind: JobKind) async {
        await perform {
            guard !installPath.isEmpty else {
                message = "请先选择安装目录"
                return
            }
            let client = try requireClient()
            let request = StartJobRequest(kind: kind, installPath: installPath)
            let job: GameJob = try await client.post("/v1/game/jobs", body: request)
            gameJob = job
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
        await perform {
            let client = try requireClient()
            let _: EmptyResponse = try await client.post("/v1/game/launch")
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

