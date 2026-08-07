import Foundation

actor CoreGameLaunchService {
    private struct State {
        var launch: GameLaunch
        var subscribers: [UUID: AsyncThrowingStream<GameLaunch, Error>.Continuation] = [:]
    }

    private let dataDirectory: URL
    private let runtimeRoot: URL
    private let accounts: CoreAccountService
    private let provider: any GameProvider
    private let runner: any CoreProcessRunning
    private let prefixManager: WinePrefixManager
    private let windowProbe: any WindowProbing
    private let mhypbaseIntegrity: MhypbaseIntegrity
    private let operationCoordinator: GameOperationCoordinator
    private var states: [String: State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var dnsLineOffsets: [String: Int] = [:]
    private var wineLogOffsets: [String: Int64] = [:]
    private var wineLogRemainders: [String: String] = [:]
    private var logWatchers: [String: Task<Void, Never>] = [:]
    private var recoveryPending = false
    private var recoveryWarnings: [String] = []
    private var recoveryWatcher: Task<Void, Never>?
    private var shuttingDown = false

    init(
        dataDirectory: URL,
        runtimeRoot: URL,
        accounts: CoreAccountService,
        provider: any GameProvider,
        runner: any CoreProcessRunning = FoundationProcessRunner(),
        prefixManager: WinePrefixManager = WinePrefixManager(),
        windowProbe: any WindowProbing = FoundationWindowProbe(),
        mhypbaseIntegrity: MhypbaseIntegrity = .pinned,
        operationCoordinator: GameOperationCoordinator = GameOperationCoordinator()
    ) {
        self.dataDirectory = dataDirectory
        self.runtimeRoot = runtimeRoot
        self.accounts = accounts
        self.provider = provider
        self.runner = runner
        self.prefixManager = prefixManager
        self.windowProbe = windowProbe
        self.mhypbaseIntegrity = mhypbaseIntegrity
        self.operationCoordinator = operationCoordinator
        let recovery = MhypbaseManager.recover(
            dataDirectory: dataDirectory,
            gameRunning: MhypbaseManager.isGameRunning()
        )
        let persistedWarnings = Self.loadRecoveryWarnings(dataDirectory: dataDirectory)
        self.recoveryPending = recovery.pending
        self.recoveryWarnings = Self.unique(persistedWarnings + recovery.warnings)
        Self.persistRecoveryWarnings(self.recoveryWarnings, dataDirectory: dataDirectory)
        for launch in Self.loadPersisted(dataDirectory: dataDirectory) {
            let terminal = Self.terminal(launch.status)
            let normalized = terminal || recovery.pending ? launch : Self.copy(
                launch, status: .exited, message: "上次启动会话已结束，临时文件将在启动时恢复", progress: 1
            )
            states[normalized.id] = State(launch: normalized)
            if !terminal { try? Self.persist(normalized, dataDirectory: dataDirectory) }
        }
        recoveryWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.refreshRecovery()
            }
        }
    }

    func start(_ request: StartGameLaunchRequest) async throws -> GameLaunch {
        guard !shuttingDown else {
            throw LauncherCoreError(code: "game_launch_unavailable", message: "游戏启动服务正在退出")
        }
        guard (0...240).contains(request.framePacing) else {
            throw LauncherCoreError(code: "game_launch_request_invalid", message: "游戏启动参数无效")
        }
        refreshRecovery()
        pruneTerminal()
        let installPath = try GameFilesystem.validatedPath(request.installPath)
        guard !states.values.contains(where: { !Self.terminal($0.launch.status) }) else {
            throw LauncherCoreError(code: "game_launch_busy", message: "游戏正在启动或运行")
        }
        let lease = try await operationCoordinator.acquire(.launch)
        do {
            guard !shuttingDown else {
                throw LauncherCoreError(code: "game_launch_unavailable", message: "游戏启动服务正在退出")
            }
            guard !states.values.contains(where: { !Self.terminal($0.launch.status) }) else {
                throw LauncherCoreError(code: "game_launch_busy", message: "游戏正在启动或运行")
            }
            guard let detected = GameFilesystem.detect(at: installPath) else {
                throw LauncherCoreError(code: "game_not_installed", message: "所选目录中未检测到可启动的原神客户端")
            }
            try PrivateFilesystem.rejectSymbolicLinksRecursively(in: detected.path)
            try GameFilesystem.ensureConfiguration(root: detected.path, version: detected.version)
            let id = UUID().uuidString
            let now = CoreDate.string(Date())
            let launch = GameLaunch(
                id: id, status: .preparing, message: "", performanceProfile: request.performanceProfile,
                metalHud: request.metalHud, networkDebug: request.networkDebug, wineLog: request.wineLog,
                progress: 0.05, logs: [GameLaunchLog(sequence: 1, timestamp: now, kind: "launch", message: "启动任务已创建")],
                startedAt: now, updatedAt: now, revision: 0
            )
            try Self.persist(launch, dataDirectory: dataDirectory)
            states[id] = State(launch: launch)
            tasks[id] = Task { [weak self] in
                await self?.execute(id: id, gameRoot: detected.path, request: request, lease: lease)
            }
            return launch
        } catch {
            await operationCoordinator.release(lease)
            throw error
        }
    }

    nonisolated func events(_ id: String, after revision: Int?) -> AsyncThrowingStream<GameLaunch, Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            Task { await self.register(id, after: revision, token: token, continuation: continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id, token: token) } }
        }
    }

    func stop(_ id: String) async throws -> GameLaunch {
        guard let state = states[id] else {
            throw LauncherCoreError(code: "game_launch_missing", message: "游戏启动会话不存在")
        }
        guard !Self.terminal(state.launch.status) else { return state.launch }
        update(id, status: .stopping, message: "正在安全停止游戏")
        tasks[id]?.cancel()
        await runner.terminate()
        return states[id]?.launch ?? state.launch
    }

    func recovery() -> GameLaunchRecovery {
        refreshRecovery()
        return GameLaunchRecovery(pending: recoveryPending, warnings: recoveryWarnings)
    }

    func runWineTool(_ request: WineToolRequest) async throws {
        guard !shuttingDown else {
            throw LauncherCoreError(code: "wine_tool_unavailable", message: "Wine 工具服务正在退出")
        }
        guard !states.values.contains(where: { !Self.terminal($0.launch.status) }) else {
            throw LauncherCoreError(code: "wine_tool_busy", message: "游戏或其他 Wine 工具正在启动")
        }
        let lease = try await operationCoordinator.acquire(.launch)
        do {
            try await performWineTool(request)
            await operationCoordinator.release(lease)
        } catch {
            await operationCoordinator.release(lease)
            throw error
        }
    }

    private func performWineTool(_ request: WineToolRequest) async throws {
        let paths = try WineRuntimePaths(root: runtimeRoot)
        let prefix = try await prefixManager.prepare(
            paths: paths,
            dataDirectory: dataDirectory,
            profile: request.performanceProfile,
            configure: false
        )
        if request.action == .explorer {
            try await runner.startDetached(CoreProcessRequest(
                executable: URL(filePath: "/usr/bin/open"), arguments: [prefix.appending(path: "drive_c").path],
                workingDirectory: nil, environment: CoreProcessEnvironment.sanitizedCurrentProcess(), logURL: nil
            ))
            return
        }
        let arguments: [String]
        if request.action == .preferences {
            arguments = ["winecfg.exe"]
        } else {
            guard let command = request.command?.trimmingCharacters(in: .whitespacesAndNewlines).nonempty else {
                throw LauncherCoreError(code: "wine_command_missing", message: "请输入要运行的 Windows 命令")
            }
            var parsed = try LaunchArgumentParser.parse(command)
            if let executable = parsed.first?.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last?.lowercased(),
               executable == "cmd" || executable == "cmd.exe" {
                parsed.insert("wineconsole.exe", at: 0)
            }
            arguments = parsed
        }
        try await runner.startDetached(CoreProcessRequest(
            executable: paths.wine, arguments: arguments, workingDirectory: nil,
            environment: await prefixManager.environment(prefix: prefix, profile: request.performanceProfile), logURL: nil
        ))
    }

    func shutdown() async {
        shuttingDown = true
        recoveryWatcher?.cancel()
        recoveryWatcher = nil
        for watcher in logWatchers.values { watcher.cancel() }
        logWatchers.removeAll()
        let active = tasks
        for task in active.values { task.cancel() }
        await runner.terminate()
        for task in active.values { await task.value }
        let activeIDs = states.compactMap { id, state in Self.terminal(state.launch.status) ? nil : id }
        for id in activeIDs {
            update(id, status: .stopped, message: "应用退出，游戏启动会话已停止", progress: 1)
        }
    }

    private func execute(
        id: String,
        gameRoot: URL,
        request: StartGameLaunchRequest,
        lease: UUID
    ) async {
        let session = dataDirectory.appending(path: "launches/\(id)")
        var journal: MhypbaseJournal?
        var preparedPaths: WineRuntimePaths?
        var preparedPrefix: URL?
        var runtimeStopPending = false
        do {
            update(id, status: .preparing, message: "正在校验并准备游戏文件", progress: 0.1)
            let paths = try WineRuntimePaths(root: runtimeRoot)
            preparedPaths = paths
            journal = try await MhypbaseManager.prepare(
                gameRoot: gameRoot, source: paths.mhypbase,
                sessionDirectory: session, integrity: mhypbaseIntegrity
            )
            update(id, status: .preparing, message: "游戏文件准备完成", progress: 0.22)
            update(id, status: .preparing, message: "正在初始化 Wine 容器", progress: 0.3)
            let prefix = try await prefixManager.prepare(paths: paths, dataDirectory: dataDirectory, profile: request.performanceProfile)
            preparedPrefix = prefix
            update(id, status: .starting, message: "Wine 容器已切换为简体中文", progress: 0.55)
            let credential = try? await accounts.credential()
            let ticket: String?
            if let credential {
                ticket = try await provider.authTicket(credential: credential)
            } else {
                ticket = nil
            }
            if ticket != nil {
                update(id, status: .starting, message: "已准备米游社账号登录票据", progress: 0.62)
            }
            let environment = try paths.environment(
                prefix: prefix, session: session, profile: request.performanceProfile,
                metalHUD: request.metalHud, networkDebug: request.networkDebug,
                wineLog: request.wineLog, framePacing: request.framePacing
            )
            var arguments = ["YuanShen.exe", "-force-d3d11"]
            arguments += try LaunchArgumentParser.parse(request.launchArguments)
            if let ticket { arguments.append("login_auth_ticket=\(ticket)") }
            update(id, status: .starting, message: "正在创建游戏进程", progress: 0.68)
            let code = try await runGame(id: id, paths: paths, request: CoreProcessRequest(
                executable: paths.wine, arguments: arguments, workingDirectory: gameRoot,
                environment: environment,
                logURL: request.wineLog ? session.appending(path: "wine.log") : dataDirectory.appending(path: "logs/game-launch.log")
            ))
            refreshLogs(id)
            do {
                try await cleanupRuntime(paths: paths, prefix: prefix, session: session)
            } catch {
                runtimeStopPending = true
                throw error
            }
            let stopping = states[id]?.launch.status == .stopping
            let warning = try MhypbaseManager.restore(journal)
            update(
                id, status: stopping ? .stopped : (code == 0 ? .exited : .failed),
                message: warning.nonempty ?? (stopping ? "游戏已停止" : code == 0 ? "游戏已正常退出" : "游戏进程退出码：\(code)"),
                progress: 1
            )
        } catch is CancellationError {
            let runtimeStopped = await cleanupRuntimeIgnoringFailure(
                paths: preparedPaths, prefix: preparedPrefix, session: session
            )
            refreshLogs(id)
            let warning = runtimeStopWarning(
                pending: runtimeStopPending || !runtimeStopped, journal: journal
            )
            update(id, status: .stopped, message: warning.nonempty ?? "游戏已停止", progress: 1)
        } catch let error as LauncherCoreError {
            let runtimeStopped = await cleanupRuntimeIgnoringFailure(
                paths: preparedPaths, prefix: preparedPrefix, session: session
            )
            refreshLogs(id)
            let warning = runtimeStopWarning(
                pending: runtimeStopPending || !runtimeStopped, journal: journal
            )
            update(id, status: .failed, message: warning.nonempty.map { "\(error.message)；\($0)" } ?? error.message)
        } catch {
            let runtimeStopped = await cleanupRuntimeIgnoringFailure(
                paths: preparedPaths, prefix: preparedPrefix, session: session
            )
            refreshLogs(id)
            let warning = runtimeStopWarning(
                pending: runtimeStopPending || !runtimeStopped, journal: journal
            )
            update(id, status: .failed, message: warning.nonempty ?? "游戏启动失败，请稍后重试")
        }
        await operationCoordinator.release(lease)
        tasks[id] = nil
    }

    private func runGame(id: String, paths: WineRuntimePaths, request: CoreProcessRequest) async throws -> Int32 {
        let snapshot = try await windowProbe.snapshot(executable: paths.windowProbe)
        let gameTask = Task { try await runner.run(request) }
        do {
            var processID: Int32?
            for _ in 0..<40 {
                if let value = await runner.processIdentifier() { processID = value; break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard let processID else { return try await gameTask.value }
            update(id, status: .waitingWindow, message: "游戏进程已创建，正在等待窗口", progress: 0.82)
            var processReported = false
            for _ in 0..<120 {
                try Task.checkCancellation()
                guard await runner.processIdentifier() != nil else { break }
                let status = try await windowProbe.status(
                    executable: paths.windowProbe, processID: processID, snapshot: snapshot
                )
                if status == 0 {
                    if let gate = request.environment["MHG_DNS_GATE_FILE"] {
                        try? PrivateFilesystem.rejectSymbolicLinks(in: URL(filePath: gate))
                        try? PrivateFilesystem.removeRegularFileIfPresent(URL(filePath: gate))
                    }
                    update(id, status: .running, message: "游戏窗口已显示，域名屏蔽已解除", progress: 1)
                    break
                }
                if status == 3, !processReported {
                    processReported = true
                    update(id, status: .waitingWindow, message: "游戏进程已创建，正在等待窗口", progress: 0.9)
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            if let gate = request.environment["MHG_DNS_GATE_FILE"] {
                try? PrivateFilesystem.rejectSymbolicLinks(in: URL(filePath: gate))
                try? PrivateFilesystem.removeRegularFileIfPresent(URL(filePath: gate))
            }
            if states[id]?.launch.status == .waitingWindow {
                update(id, status: .running, message: "窗口探针超时，已自动解除域名屏蔽", progress: 1)
            }
            return try await gameTask.value
        } catch {
            gameTask.cancel()
            await runner.terminate()
            _ = try? await gameTask.value
            throw error
        }
    }

    private func cleanupRuntime(paths: WineRuntimePaths, prefix: URL, session: URL) async throws {
        try PrivateFilesystem.rejectSymbolicLinks(in: session.appending(path: "dns-gate"))
        try? PrivateFilesystem.removeRegularFileIfPresent(session.appending(path: "dns-gate"))
        try await Task.detached { [prefixManager] in
            try await prefixManager.stopServer(paths: paths, prefix: prefix)
        }.value
    }

    private func cleanupRuntimeIgnoringFailure(
        paths: WineRuntimePaths?,
        prefix: URL?,
        session: URL
    ) async -> Bool {
        try? PrivateFilesystem.rejectSymbolicLinks(in: session.appending(path: "dns-gate"))
        try? PrivateFilesystem.removeRegularFileIfPresent(session.appending(path: "dns-gate"))
        guard let paths, let prefix else { return true }
        do {
            try await Task.detached { [prefixManager] in
                try await prefixManager.stopServer(paths: paths, prefix: prefix)
            }.value
            return true
        } catch {
            return false
        }
    }

    private func runtimeStopWarning(pending: Bool, journal: MhypbaseJournal?) -> String {
        guard pending else { return (try? MhypbaseManager.restore(journal)) ?? "" }
        return "Wine 进程尚未确认退出，DLL 会话记录已交由恢复任务"
    }

    private func register(
        _ id: String,
        after revision: Int?,
        token: UUID,
        continuation: AsyncThrowingStream<GameLaunch, Error>.Continuation
    ) {
        guard states[id] != nil else {
            continuation.finish(throwing: LauncherCoreError(code: "game_launch_missing", message: "游戏启动会话不存在"))
            return
        }
        refreshLogs(id)
        guard var state = states[id] else {
            continuation.finish(throwing: LauncherCoreError(code: "game_launch_missing", message: "游戏启动会话不存在"))
            return
        }
        if (state.launch.revision ?? 0) > (revision ?? -1) { continuation.yield(state.launch) }
        if Self.terminal(state.launch.status) { continuation.finish(); return }
        state.subscribers[token] = continuation
        states[id] = state
        startLogWatcher(id)
    }

    private func unregister(_ id: String, token: UUID) {
        states[id]?.subscribers[token] = nil
        if states[id]?.subscribers.isEmpty == true {
            logWatchers[id]?.cancel()
            logWatchers[id] = nil
        }
    }

    private func update(_ id: String, status: GameLaunchStatus, message: String, progress: Double? = nil) {
        guard var state = states[id] else { return }
        state.launch = Self.copy(state.launch, status: status, message: message, progress: progress)
        states[id] = state
        try? Self.persist(state.launch, dataDirectory: dataDirectory)
        for subscriber in state.subscribers.values {
            subscriber.yield(state.launch)
            if Self.terminal(status) { subscriber.finish() }
        }
        if Self.terminal(status) { states[id]?.subscribers.removeAll() }
        if Self.terminal(status) {
            logWatchers[id]?.cancel()
            logWatchers[id] = nil
        }
    }

    private func startLogWatcher(_ id: String) {
        guard logWatchers[id] == nil else { return }
        logWatchers[id] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.refreshLogs(id)
                if await self.isTerminal(id) { return }
            }
        }
    }

    private func isTerminal(_ id: String) -> Bool {
        guard let state = states[id] else { return true }
        return Self.terminal(state.launch.status)
    }

    private func refreshLogs(_ id: String) {
        guard let state = states[id] else { return }
        var additions: [GameLaunchLog] = []
        if state.launch.networkDebug {
            additions.append(contentsOf: readDNSLogs(id: id))
        }
        if state.launch.wineLog {
            additions.append(contentsOf: readWineLogs(id: id))
        }
        guard !additions.isEmpty, var current = states[id] else { return }
        var logs = current.launch.logs
        for addition in additions {
            logs.append(GameLaunchLog(
                sequence: (logs.last?.sequence ?? 0) + 1,
                timestamp: addition.timestamp,
                kind: addition.kind,
                message: addition.message
            ))
        }
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        current.launch = Self.copy(current.launch, logs: logs)
        states[id] = current
        try? Self.persist(current.launch, dataDirectory: dataDirectory)
        for subscriber in current.subscribers.values { subscriber.yield(current.launch) }
    }

    private func readDNSLogs(id: String) -> [GameLaunchLog] {
        let url = dataDirectory.appending(path: "launches/\(id)/dns.log")
        guard GameFilesystem.regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let previous = dnsLineOffsets[id] ?? 0
        let offset = previous <= lines.count ? previous : 0
        dnsLineOffsets[id] = lines.count
        return lines.dropFirst(offset).compactMap(Self.parseDNSLog)
    }

    private func readWineLogs(id: String) -> [GameLaunchLog] {
        let url = dataDirectory.appending(path: "launches/\(id)/wine.log")
        guard GameFilesystem.regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize, size <= 64 * 1024 * 1024 else { return [] }
        let previous = wineLogOffsets[id] ?? 0
        let offset = previous <= Int64(size) ? previous : 0
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: min(Int64(256 * 1024), Int64(size) - offset)) ?? Data()
            wineLogOffsets[id] = offset + Int64(data.count)
            let text = wineLogRemainders[id].map { $0 + (String(data: data, encoding: .utf8) ?? "") }
                ?? (String(data: data, encoding: .utf8) ?? "")
            guard !text.isEmpty else { return [] }
            let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let complete = text.last == "\n" ? parts : Array(parts.dropLast())
            wineLogRemainders[id] = text.last == "\n" ? "" : parts.last ?? ""
            return complete.suffix(30).compactMap { line in
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, value.utf8.count <= 4_096 else { return nil }
                return GameLaunchLog(sequence: 0, timestamp: CoreDate.string(Date()), kind: "wine", message: String(value.prefix(500)))
            }
        } catch {
            return []
        }
    }

    private static func parseDNSLog(_ line: String) -> GameLaunchLog? {
        guard line.utf8.count <= 4_096 else { return nil }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 6,
              let milliseconds = Int64(fields[0]),
              milliseconds >= 0,
              fields[1].utf8.count <= 64,
              fields[2].utf8.count <= 128,
              fields[3].utf8.count <= 256,
              fields[4].utf8.count <= 64,
              fields[5].utf8.count <= 64 else { return nil }
        let result = String(fields[5])
        let state: String
        if fields[4] == "blocked" {
            state = "屏蔽"
        } else if Int(result) == 0 {
            let address = fields.count > 6 && fields[6].utf8.count <= 256 ? String(fields[6]) : ""
            state = address.isEmpty ? "成功" : "成功 → \(address)"
        } else {
            state = "未找到 \(result)"
        }
        return GameLaunchLog(
            sequence: 0,
            timestamp: CoreDate.string(Date(timeIntervalSince1970: Double(milliseconds) / 1_000)),
            kind: "dns",
            message: "DNS · PID \(fields[1]) · \(fields[2]) · \(fields[3]) · \(state)"
        )
    }

    private func refreshRecovery() {
        let wasPending = recoveryPending
        let result = MhypbaseManager.recover(
            dataDirectory: dataDirectory,
            gameRunning: MhypbaseManager.isGameRunning()
        )
        recoveryPending = result.pending
        let merged = Self.unique(recoveryWarnings + result.warnings)
        if merged != recoveryWarnings {
            recoveryWarnings = merged
            Self.persistRecoveryWarnings(merged, dataDirectory: dataDirectory)
        }
        if wasPending && !result.pending {
            finishRecovered()
        }
    }

    private func finishRecovered() {
        let message = recoveryWarnings.last ?? "游戏已退出，DLL 会话已由恢复任务清理"
        let activeIDs = states.compactMap { id, state in
            Self.terminal(state.launch.status) ? nil : id
        }
        for id in activeIDs {
            update(id, status: .exited, message: message, progress: 1)
        }
    }

    private static func copy(
        _ value: GameLaunch,
        status: GameLaunchStatus,
        message: String,
        progress: Double? = nil
    ) -> GameLaunch {
        let now = CoreDate.string(Date())
        var logs = value.logs
        if !message.isEmpty {
            logs.append(GameLaunchLog(sequence: (logs.last?.sequence ?? 0) + 1, timestamp: now, kind: "launch", message: message))
        }
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        return GameLaunch(
            id: value.id, status: status, message: message, performanceProfile: value.performanceProfile,
            metalHud: value.metalHud, networkDebug: value.networkDebug, wineLog: value.wineLog,
            progress: max(value.progress, min(progress ?? value.progress, 1)), logs: logs,
            startedAt: value.startedAt, updatedAt: now, revision: (value.revision ?? 0) + 1
        )
    }

    private static func copy(_ value: GameLaunch, logs: [GameLaunchLog]) -> GameLaunch {
        GameLaunch(
            id: value.id, status: value.status, message: value.message,
            performanceProfile: value.performanceProfile, metalHud: value.metalHud,
            networkDebug: value.networkDebug, wineLog: value.wineLog, progress: value.progress,
            logs: logs, startedAt: value.startedAt, updatedAt: CoreDate.string(Date()),
            revision: (value.revision ?? 0) + 1
        )
    }

    private static func terminal(_ status: GameLaunchStatus) -> Bool {
        [.stopped, .exited, .failed].contains(status)
    }

    private static func persist(_ launch: GameLaunch, dataDirectory: URL) throws {
        guard validSessionID(launch.id) else {
            throw LauncherCoreError(code: "game_launch_invalid", message: "游戏启动会话标识无效")
        }
        try GameFilesystem.writePrivate(
            JSONEncoder.api.encode(launch),
            to: dataDirectory.appending(path: "launches/\(launch.id)/status.json")
        )
    }

    private static func loadPersisted(dataDirectory: URL) -> [GameLaunch] {
        let root = dataDirectory.appending(path: "launches")
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: root)) != nil,
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: nil,
                  options: [.skipsSubdirectoryDescendants]
              ) else { return [] }
        var entries: [URL] = []
        while let entry = enumerator.nextObject() as? URL {
            entries.append(entry)
            guard entries.count <= 256 else { return [] }
        }
        return entries.compactMap { entry in
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  validSessionID(entry.lastPathComponent) else { return nil }
            let status = entry.appending(path: "status.json")
            guard GameFilesystem.regularFile(status),
                  let values = try? status.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= 1024 * 1024,
                  let data = try? Data(contentsOf: status) else { return nil }
            guard let launch = try? JSONDecoder.api.decode(GameLaunch.self, from: data),
                  launch.id == entry.lastPathComponent,
                  launch.logs.count <= 200,
                  launch.message.utf8.count <= 4_096,
                  launch.progress.isFinite, (0...1).contains(launch.progress),
                  (launch.revision ?? 0) >= 0,
                  launch.startedAt.utf8.count <= 128,
                  launch.updatedAt.utf8.count <= 128,
                  launch.logs.allSatisfy({
                      $0.sequence >= 0 && $0.kind.utf8.count <= 64
                          && $0.message.utf8.count <= 4_096
                          && $0.timestamp.utf8.count <= 128
                  }) else { return nil }
            return launch
        }
    }

    private static func validSessionID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    private struct RecoveryWarnings: Codable {
        let warnings: [String]
    }

    private static func loadRecoveryWarnings(dataDirectory: URL) -> [String] {
        let url = dataDirectory.appending(path: "launches/recovery-warnings.json")
        guard GameFilesystem.regularFile(url),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder.api.decode(RecoveryWarnings.self, from: data) else {
            return []
        }
        return Self.unique(value.warnings.filter { $0.utf8.count <= 4_096 })
    }

    private static func persistRecoveryWarnings(_ warnings: [String], dataDirectory: URL) {
        guard !warnings.isEmpty else { return }
        let value = RecoveryWarnings(warnings: Array(warnings.suffix(256)))
        guard let data = try? JSONEncoder.api.encode(value) else { return }
        try? GameFilesystem.writePrivate(
            data,
            to: dataDirectory.appending(path: "launches/recovery-warnings.json")
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func pruneTerminal() {
        let now = Date()
        let candidates = states
            .filter { Self.terminal($0.value.launch.status) }
            .sorted { CoreDate.parse($0.value.launch.updatedAt) < CoreDate.parse($1.value.launch.updatedAt) }
        for (id, state) in candidates {
            let age = now.timeIntervalSince(CoreDate.parse(state.launch.updatedAt))
            guard age >= 60 * 60 || states.count >= 100 else { continue }
            let directory = dataDirectory.appending(path: "launches").appending(path: id)
            guard validSessionID(id),
                  !FileManager.default.fileExists(atPath: directory.appending(path: "dll-journal.json").path),
                  (try? PrivateFilesystem.removeDirectoryIfPresent(directory)) != nil else { continue }
            states[id] = nil
        }
    }
}
