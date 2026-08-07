import Foundation

actor GameJobControl {
    private var paused = false
    private var cancelled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pauseAcknowledged = false
    private var pauseWaiters: [CheckedContinuation<Bool, Never>] = []

    func pause() {
        paused = true
        pauseAcknowledged = false
    }

    func waitForPauseAcknowledgement() async -> Bool {
        guard !cancelled, paused else { return false }
        if pauseAcknowledged { return true }
        return await withCheckedContinuation { continuation in
            if cancelled || !paused {
                continuation.resume(returning: false)
            } else if pauseAcknowledged {
                continuation.resume(returning: true)
            } else {
                pauseWaiters.append(continuation)
            }
        }
    }

    func resume() {
        paused = false
        releaseWaiters()
        let acknowledgements = pauseWaiters
        pauseWaiters.removeAll()
        acknowledgements.forEach { $0.resume(returning: false) }
    }

    func cancel() {
        cancelled = true
        paused = false
        releaseWaiters()
        let acknowledgements = pauseWaiters
        pauseWaiters.removeAll()
        acknowledgements.forEach { $0.resume(returning: false) }
    }

    func finish() {
        cancelled = true
        paused = false
        releaseWaiters()
        let acknowledgements = pauseWaiters
        pauseWaiters.removeAll()
        acknowledgements.forEach { $0.resume(returning: false) }
    }

    func checkpoint() async throws {
        if cancelled { throw CancellationError() }
        if paused {
            pauseAcknowledged = true
            let acknowledgements = pauseWaiters
            pauseWaiters.removeAll()
            acknowledgements.forEach { $0.resume(returning: true) }
            await withCheckedContinuation { waiters.append($0) }
        }
        if cancelled { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func releaseWaiters() {
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
}

actor GameJobCoordinator {
    typealias Operation = @Sendable (String, GameJobControl) async throws -> Void

    private struct State {
        var job: GameJob
        let control: GameJobControl
        var subscribers: [UUID: AsyncThrowingStream<GameJob, Error>.Continuation] = [:]
        var completedChunks: Set<String> = []
        var speedBytes: Int64 = 0
        var speedStartedAt = Date()
    }

    private var states: [String: State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var pauseTasks: [String: Task<Void, Never>] = [:]
    private var shuttingDown = false

    func start(
        kind: JobKind,
        total: Int64,
        message: String = "任务已排队",
        chunksTotal: Int64 = 0,
        operation: @escaping Operation
    ) throws -> GameJob {
        guard !shuttingDown else {
            throw LauncherCoreError(code: "game_resource_unavailable", message: "游戏资源服务正在退出")
        }
        states = states.filter { !terminal($0.value.job.status) }
        guard !states.values.contains(where: { [.queued, .running, .pausing, .paused, .cancelling].contains($0.job.status) }) else {
            throw LauncherCoreError(code: "game_resource_busy", message: "已有游戏资源任务正在运行")
        }
        let id = UUID().uuidString
        let job = GameJob(
            id: id, kind: kind, status: .queued, completedBytes: 0, totalBytes: max(0, total),
            message: message, downloadSpeed: 0, chunksCompleted: 0, chunksTotal: max(0, chunksTotal),
            activeChunks: [], lastUpdate: "", revision: 0
        )
        let control = GameJobControl()
        states[id] = State(job: job, control: control)
        tasks[id] = Task { [weak self] in
            await self?.replace(id, status: .running, message: "任务正在运行")
            do {
                try await operation(id, control)
                await control.finish()
                await self?.replace(id, status: .completed, message: "任务已完成", finishProgress: true)
            } catch is CancellationError {
                await control.finish()
                await self?.replace(id, status: .cancelled, message: "任务已取消")
            } catch let error as LauncherCoreError {
                await control.finish()
                await self?.replace(id, status: .failed, message: error.message)
            } catch {
                await control.finish()
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
        activeChunks: [ChunkProgress]? = nil,
        chunk: ChunkProgress? = nil
    ) {
        guard var state = states[id] else { return }
        let boundedTotal = max(total ?? state.job.totalBytes, 0)
        let boundedCompleted = min(max(0, completed), boundedTotal)
        let delta = max(0, boundedCompleted - state.job.completedBytes)
        state.speedBytes = state.speedBytes > Int64.max - delta
            ? Int64.max : state.speedBytes + delta
        let now = Date()
        let elapsed = now.timeIntervalSince(state.speedStartedAt)
        var downloadSpeed = state.job.downloadSpeed
        if elapsed >= 0.5 {
            downloadSpeed = Int64(Double(state.speedBytes) / elapsed)
            state.speedBytes = 0
            state.speedStartedAt = now
        }
        var chunks = activeChunks ?? state.job.activeChunks
        if let chunk {
            let boundedChunk = ChunkProgress(
                name: chunk.name,
                bytesDone: min(max(0, chunk.bytesDone), max(0, chunk.total)),
                total: max(0, chunk.total)
            )
            chunks.removeAll { $0.name == boundedChunk.name }
            if boundedChunk.total > 0, boundedChunk.bytesDone >= boundedChunk.total {
                state.completedChunks.insert(boundedChunk.name)
            } else {
                chunks.append(boundedChunk)
            }
        }
        state.job = copy(
            state.job,
            completed: boundedCompleted,
            total: boundedTotal,
            message: message ?? state.job.message,
            downloadSpeed: downloadSpeed,
            chunksCompleted: min(state.job.chunksTotal, Int64(state.completedChunks.count)),
            activeChunks: chunks
        )
        states[id] = state
        publish(id)
    }

    func addProgress(_ id: String, bytes: Int64, message: String? = nil) {
        guard let state = states[id] else { return }
        let completed = bytes >= 0
            ? state.job.completedBytes > Int64.max - bytes ? Int64.max : state.job.completedBytes + bytes
            : max(0, state.job.completedBytes + bytes)
        progress(id, completed: completed, message: message)
    }

    func markChunks(_ id: String, names: [String]) {
        guard var state = states[id] else { return }
        for name in names where !name.isEmpty { state.completedChunks.insert(name) }
        state.job = copy(
            state.job,
            chunksCompleted: min(state.job.chunksTotal, Int64(state.completedChunks.count))
        )
        states[id] = state
        publish(id)
    }

    func control(_ id: String, action: String) async throws -> GameJob {
        guard var state = states[id] else {
            throw LauncherCoreError(code: "game_job_not_found", message: "游戏资源任务不存在")
        }
        switch action {
        case "cancel" where [.completed, .cancelled, .failed].contains(state.job.status):
            return state.job
        case "pause" where state.job.status == .running:
            await state.control.pause()
            state.job = copy(state.job, status: .pausing, message: "正在暂停任务")
            let control = state.control
            pauseTasks[id]?.cancel()
            pauseTasks[id] = Task { [weak self, control] in
                guard await control.waitForPauseAcknowledgement() else { return }
                await self?.acknowledgePause(id)
            }
        case "resume" where state.job.status == .paused:
            state.job = copy(state.job, status: .running, message: "任务正在运行")
            pauseTasks[id]?.cancel()
            pauseTasks[id] = nil
            await state.control.resume()
        case "cancel" where ![.completed, .cancelled, .failed].contains(state.job.status):
            state.job = copy(state.job, status: .cancelling, message: "正在取消任务")
            pauseTasks[id]?.cancel()
            pauseTasks[id] = nil
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
        shuttingDown = true
        let active = tasks
        for (id, task) in active {
            pauseTasks[id]?.cancel()
            pauseTasks[id] = nil
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
            downloadSpeed: terminal(status) ? 0 : state.job.downloadSpeed,
            chunksCompleted: finishProgress ? state.job.chunksTotal : state.job.chunksCompleted,
            activeChunks: terminal(status) ? [] : state.job.activeChunks
        )
        states[id] = state
        publish(id)
        if terminal(status) {
            pauseTasks[id]?.cancel()
            pauseTasks[id] = nil
            tasks[id] = nil
        }
    }

    private func acknowledgePause(_ id: String) {
        guard var state = states[id], state.job.status == .pausing else { return }
        state.job = copy(state.job, status: .paused, message: "任务已暂停")
        states[id] = state
        pauseTasks[id] = nil
        publish(id)
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
        downloadSpeed: Int64? = nil,
        chunksCompleted: Int64? = nil,
        chunksTotal: Int64? = nil,
        activeChunks: [ChunkProgress]? = nil
    ) -> GameJob {
        GameJob(
            id: value.id, kind: value.kind, status: status ?? value.status,
            completedBytes: completed ?? value.completedBytes, totalBytes: total ?? value.totalBytes,
            message: message ?? value.message, downloadSpeed: downloadSpeed ?? value.downloadSpeed,
            chunksCompleted: chunksCompleted ?? value.chunksCompleted,
            chunksTotal: chunksTotal ?? value.chunksTotal,
            activeChunks: activeChunks ?? value.activeChunks, lastUpdate: CoreDate.string(Date()),
            revision: (value.revision ?? 0) + 1
        )
    }
}
