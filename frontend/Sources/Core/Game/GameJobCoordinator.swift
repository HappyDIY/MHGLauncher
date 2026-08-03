import Foundation

actor GameJobControl {
    private var paused = false
    private var cancelled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pause() { paused = true }
    func resume() {
        paused = false
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
    func cancel() {
        cancelled = true
        resume()
    }
    func checkpoint() async throws {
        if cancelled { throw CancellationError() }
        if paused { await withCheckedContinuation { waiters.append($0) } }
        if cancelled { throw CancellationError() }
        try Task.checkCancellation()
    }
}

actor GameJobCoordinator {
    typealias Operation = @Sendable (String, GameJobControl) async throws -> Void

    private struct State {
        var job: GameJob
        let control: GameJobControl
        var subscribers: [UUID: AsyncThrowingStream<GameJob, Error>.Continuation] = [:]
    }

    private var states: [String: State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    func start(kind: JobKind, total: Int64, operation: @escaping Operation) throws -> GameJob {
        guard !states.values.contains(where: { [.queued, .running, .pausing, .paused, .cancelling].contains($0.job.status) }) else {
            throw LauncherCoreError(code: "game_resource_busy", message: "已有游戏资源任务正在运行")
        }
        let id = UUID().uuidString
        let now = CoreDate.string(Date())
        let job = GameJob(
            id: id, kind: kind, status: .queued, completedBytes: 0, totalBytes: max(0, total),
            message: "任务已排队", downloadSpeed: 0, chunksCompleted: 0, chunksTotal: 0,
            activeChunks: [], lastUpdate: now, revision: 0
        )
        let control = GameJobControl()
        states[id] = State(job: job, control: control)
        tasks[id] = Task { [weak self] in
            await self?.replace(id, status: .running, message: "任务正在运行")
            do {
                try await operation(id, control)
                await self?.replace(id, status: .completed, message: "任务已完成", finishProgress: true)
            } catch is CancellationError {
                await self?.replace(id, status: .cancelled, message: "任务已取消")
            } catch let error as LauncherCoreError {
                await self?.replace(id, status: .failed, message: error.message)
            } catch {
                await self?.replace(id, status: .failed, message: "游戏资源任务失败")
            }
        }
        return job
    }

    func progress(
        _ id: String,
        completed: Int64,
        total: Int64? = nil,
        message: String? = nil,
        activeChunks: [ChunkProgress]? = nil
    ) {
        guard var state = states[id] else { return }
        state.job = copy(
            state.job,
            completed: min(max(0, completed), max(total ?? state.job.totalBytes, 0)),
            total: total ?? state.job.totalBytes,
            message: message ?? state.job.message,
            activeChunks: activeChunks ?? state.job.activeChunks
        )
        states[id] = state
        publish(id)
    }

    func control(_ id: String, action: String) async throws -> GameJob {
        guard var state = states[id] else {
            throw LauncherCoreError(code: "game_job_not_found", message: "游戏资源任务不存在")
        }
        switch action {
        case "pause" where state.job.status == .running:
            state.job = copy(state.job, status: .paused, message: "任务已暂停")
            await state.control.pause()
        case "resume" where state.job.status == .paused:
            state.job = copy(state.job, status: .running, message: "任务正在运行")
            await state.control.resume()
        case "cancel" where ![.completed, .cancelled, .failed].contains(state.job.status):
            state.job = copy(state.job, status: .cancelling, message: "正在取消任务")
            await state.control.cancel()
            tasks[id]?.cancel()
        default:
            throw LauncherCoreError(code: "game_job_action_invalid", message: "当前任务状态不支持此操作")
        }
        states[id] = state
        publish(id)
        return state.job
    }

    func events(_ id: String, after: Int?) -> AsyncThrowingStream<GameJob, Error> {
        AsyncThrowingStream { continuation in
            guard var state = states[id] else {
                continuation.finish(throwing: LauncherCoreError(code: "game_job_not_found", message: "游戏资源任务不存在"))
                return
            }
            let subscriber = UUID()
            if (state.job.revision ?? 0) > (after ?? -1) { continuation.yield(state.job) }
            if terminal(state.job.status) { continuation.finish(); return }
            state.subscribers[subscriber] = continuation
            states[id] = state
            continuation.onTermination = { [weak self] _ in Task { await self?.removeSubscriber(id, subscriber) } }
        }
    }

    func shutdown() async {
        let active = tasks
        for (id, task) in active {
            await states[id]?.control.cancel()
            task.cancel()
        }
        for task in active.values { await task.value }
    }

    private func replace(_ id: String, status: JobStatus, message: String, finishProgress: Bool = false) {
        guard var state = states[id] else { return }
        state.job = copy(
            state.job,
            status: status,
            completed: finishProgress ? state.job.totalBytes : state.job.completedBytes,
            message: message,
            activeChunks: terminal(status) ? [] : state.job.activeChunks
        )
        states[id] = state
        publish(id)
        if terminal(status) { tasks[id] = nil }
    }

    private func publish(_ id: String) {
        guard let state = states[id] else { return }
        for subscriber in state.subscribers.values {
            subscriber.yield(state.job)
            if terminal(state.job.status) { subscriber.finish() }
        }
        if terminal(state.job.status) {
            states[id]?.subscribers.removeAll()
        }
    }

    private func removeSubscriber(_ id: String, _ subscriber: UUID) {
        states[id]?.subscribers[subscriber] = nil
    }

    private func terminal(_ status: JobStatus) -> Bool {
        [.completed, .cancelled, .failed].contains(status)
    }

    private func copy(
        _ value: GameJob,
        status: JobStatus? = nil,
        completed: Int64? = nil,
        total: Int64? = nil,
        message: String? = nil,
        activeChunks: [ChunkProgress]? = nil
    ) -> GameJob {
        GameJob(
            id: value.id, kind: value.kind, status: status ?? value.status,
            completedBytes: completed ?? value.completedBytes, totalBytes: total ?? value.totalBytes,
            message: message ?? value.message, downloadSpeed: value.downloadSpeed,
            chunksCompleted: value.chunksCompleted, chunksTotal: value.chunksTotal,
            activeChunks: activeChunks ?? value.activeChunks, lastUpdate: CoreDate.string(Date()),
            revision: (value.revision ?? 0) + 1
        )
    }
}
