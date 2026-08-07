import Foundation

actor WishTaskCoordinator {
    private struct State {
        var snapshot: WishTaskSnapshot
        var continuations: [UUID: AsyncThrowingStream<WishTaskSnapshot, Error>.Continuation] = [:]
    }

    private var states: [String: State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    func start(
        kind: String,
        operation: @escaping @Sendable (
            @escaping @Sendable (String, Bool) async -> Void
        ) async throws -> (result: [String: Int], targetUIDs: [String]?)
    ) -> WishTaskSnapshot {
        let id = UUID().uuidString
        let initial = WishTaskSnapshot(
            id: id,
            kind: kind,
            status: .queued,
            progress: 0,
            logs: [WishTaskLogPayload(sequence: 1, message: "后端已创建任务", emphasized: false)],
            result: nil,
            error: "",
            errorCode: nil,
            revision: 1,
            targetUids: nil
        )
        states[id] = State(snapshot: initial)
        tasks[id] = Task {
            update(id: id, status: .running, progress: nil)
            do {
                let output = try await operation { [weak self] message, emphasized in
                    await self?.appendLog(id: id, message: message, emphasized: emphasized)
                }
                complete(id: id, result: output.result, targetUIDs: output.targetUIDs)
            } catch let error as LauncherCoreError {
                fail(id: id, code: error.code, message: error.message)
            } catch is CancellationError {
                fail(id: id, code: "task_cancelled", message: "任务已取消")
            } catch {
                fail(id: id, code: "task_failed", message: "祈愿任务执行失败")
            }
        }
        return initial
    }

    func shutdown() async {
        let active = tasks.values
        for task in active { task.cancel() }
        for task in active { await task.value }
    }

    nonisolated func events(
        id: String,
        after revision: Int?
    ) -> AsyncThrowingStream<WishTaskSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            Task { await self.register(id: id, after: revision, token: token, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id, token: token) }
            }
        }
    }

    private func register(
        id: String,
        after revision: Int?,
        token: UUID,
        continuation: AsyncThrowingStream<WishTaskSnapshot, Error>.Continuation
    ) {
        guard var state = states[id] else {
            continuation.finish(throwing: LauncherCoreError(
                code: "wish_task_missing",
                message: "祈愿任务不存在"
            ))
            return
        }
        if (state.snapshot.revision ?? 0) > (revision ?? 0) {
            continuation.yield(state.snapshot)
        }
        if [.completed, .failed].contains(state.snapshot.status) {
            continuation.finish()
            return
        }
        state.continuations[token] = continuation
        states[id] = state
    }

    private func unregister(id: String, token: UUID) {
        states[id]?.continuations[token] = nil
    }

    private func appendLog(id: String, message: String, emphasized: Bool) {
        guard var state = states[id] else { return }
        var logs = state.snapshot.logs
        logs.append(WishTaskLogPayload(
            sequence: (logs.last?.sequence ?? 0) + 1,
            message: message,
            emphasized: emphasized
        ))
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        state.snapshot = copy(state.snapshot, logs: logs, revision: (state.snapshot.revision ?? 0) + 1)
        states[id] = state
        publish(id)
    }

    private func update(id: String, status: WishTaskStatus, progress: Double?) {
        guard var state = states[id] else { return }
        state.snapshot = copy(
            state.snapshot,
            status: status,
            progress: progress,
            revision: (state.snapshot.revision ?? 0) + 1
        )
        states[id] = state
        publish(id)
    }

    private func complete(id: String, result: [String: Int], targetUIDs: [String]?) {
        guard var state = states[id] else { return }
        state.snapshot = copy(
            state.snapshot,
            status: .completed,
            progress: 1,
            result: result,
            revision: (state.snapshot.revision ?? 0) + 1,
            targetUIDs: targetUIDs
        )
        states[id] = state
        publish(id, terminal: true)
        tasks[id] = nil
    }

    private func fail(id: String, code: String, message: String) {
        guard var state = states[id] else { return }
        state.snapshot = copy(
            state.snapshot,
            status: .failed,
            error: message,
            errorCode: code,
            revision: (state.snapshot.revision ?? 0) + 1
        )
        states[id] = state
        publish(id, terminal: true)
        tasks[id] = nil
    }

    private func publish(_ id: String, terminal: Bool = false) {
        guard var state = states[id] else { return }
        for continuation in state.continuations.values {
            continuation.yield(state.snapshot)
            if terminal { continuation.finish() }
        }
        if terminal { state.continuations.removeAll() }
        states[id] = state
    }

    private func copy(
        _ value: WishTaskSnapshot,
        status: WishTaskStatus? = nil,
        progress: Double?? = nil,
        logs: [WishTaskLogPayload]? = nil,
        result: [String: Int]?? = nil,
        error: String? = nil,
        errorCode: String?? = nil,
        revision: Int? = nil,
        targetUIDs: [String]?? = nil
    ) -> WishTaskSnapshot {
        WishTaskSnapshot(
            id: value.id,
            kind: value.kind,
            status: status ?? value.status,
            progress: progress ?? value.progress,
            logs: logs ?? value.logs,
            result: result ?? value.result,
            error: error ?? value.error,
            errorCode: errorCode ?? value.errorCode,
            revision: revision ?? value.revision,
            targetUids: targetUIDs ?? value.targetUids
        )
    }
}
