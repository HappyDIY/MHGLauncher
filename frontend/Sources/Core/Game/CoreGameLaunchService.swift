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
    private var states: [String: State] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    init(
        dataDirectory: URL,
        runtimeRoot: URL,
        accounts: CoreAccountService,
        provider: any GameProvider,
        runner: any CoreProcessRunning = FoundationProcessRunner(),
        prefixManager: WinePrefixManager = WinePrefixManager(),
        windowProbe: any WindowProbing = FoundationWindowProbe(),
        mhypbaseIntegrity: MhypbaseIntegrity = .pinned
    ) {
        self.dataDirectory = dataDirectory
        self.runtimeRoot = runtimeRoot
        self.accounts = accounts
        self.provider = provider
        self.runner = runner
        self.prefixManager = prefixManager
        self.windowProbe = windowProbe
        self.mhypbaseIntegrity = mhypbaseIntegrity
        for launch in Self.loadPersisted(dataDirectory: dataDirectory) {
            let terminal = Self.terminal(launch.status)
            let normalized = terminal ? launch : Self.copy(
                launch, status: .exited, message: "上次启动会话已结束，临时文件将在启动时恢复", progress: 1
            )
            states[normalized.id] = State(launch: normalized)
            if !terminal { try? Self.persist(normalized, dataDirectory: dataDirectory) }
        }
        _ = MhypbaseManager.recover(
            dataDirectory: dataDirectory,
            gameRunning: MhypbaseManager.isGameRunning()
        )
    }

    func start(_ request: StartGameLaunchRequest) async throws -> GameLaunch {
        guard (0...1_000).contains(request.framePacing) else {
            throw LauncherCoreError(code: "game_launch_request_invalid", message: "游戏启动参数无效")
        }
        let installPath = try GameFilesystem.validatedPath(request.installPath)
        guard !states.values.contains(where: { !Self.terminal($0.launch.status) }) else {
            throw LauncherCoreError(code: "game_launch_busy", message: "游戏正在启动或运行")
        }
        guard let detected = GameFilesystem.detect(at: installPath) else {
            throw LauncherCoreError(code: "game_not_installed", message: "所选目录中未检测到可启动的原神客户端")
        }
        try PrivateFilesystem.rejectSymbolicLinksRecursively(in: detected.path)
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
            await self?.execute(id: id, gameRoot: detected.path, request: request)
        }
        return launch
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

    func runWineTool(_ request: WineToolRequest) async throws {
        guard !states.values.contains(where: { !Self.terminal($0.launch.status) }) else {
            throw LauncherCoreError(code: "wine_tool_busy", message: "游戏或其他 Wine 工具正在启动")
        }
        let paths = try WineRuntimePaths(root: runtimeRoot)
        let prefix = try await prefixManager.prepare(paths: paths, dataDirectory: dataDirectory, profile: request.performanceProfile)
        if request.action == .explorer {
            let status = try await runner.run(CoreProcessRequest(
                executable: URL(filePath: "/usr/bin/open"), arguments: [prefix.appending(path: "drive_c").path],
                workingDirectory: nil, environment: CoreProcessEnvironment.sanitizedCurrentProcess(), logURL: nil
            ))
            guard status == 0 else { throw LauncherCoreError(code: "wine_tool_failed", message: "无法打开 Wine 文件目录") }
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
        let status = try await runner.run(CoreProcessRequest(
            executable: paths.wine, arguments: arguments, workingDirectory: nil,
            environment: await prefixManager.environment(prefix: prefix, profile: request.performanceProfile), logURL: nil
        ))
        guard status == 0 else { throw LauncherCoreError(code: "wine_tool_failed", message: "Wine 工具启动失败") }
    }

    func shutdown() async {
        let active = tasks
        for task in active.values { task.cancel() }
        await runner.terminate()
        for task in active.values { await task.value }
        let activeIDs = states.compactMap { id, state in Self.terminal(state.launch.status) ? nil : id }
        for id in activeIDs {
            update(id, status: .stopped, message: "应用退出，游戏启动会话已停止", progress: 1)
        }
    }

    private func execute(id: String, gameRoot: URL, request: StartGameLaunchRequest) async {
        let session = dataDirectory.appending(path: "launches/\(id)")
        var journal: MhypbaseJournal?
        var preparedPaths: WineRuntimePaths?
        var preparedPrefix: URL?
        do {
            update(id, status: .preparing, message: "正在校验并准备游戏文件", progress: 0.1)
            let paths = try WineRuntimePaths(root: runtimeRoot)
            preparedPaths = paths
            journal = try await MhypbaseManager.prepare(
                gameRoot: gameRoot, source: paths.mhypbase,
                sessionDirectory: session, integrity: mhypbaseIntegrity
            )
            let prefix = try await prefixManager.prepare(paths: paths, dataDirectory: dataDirectory, profile: request.performanceProfile)
            preparedPrefix = prefix
            let credential = try? await accounts.credential()
            let ticket: String?
            if let credential {
                ticket = try await provider.authTicket(credential: credential)
            } else {
                ticket = nil
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
            try await cleanupRuntime(paths: paths, prefix: prefix, session: session)
            let stopping = states[id]?.launch.status == .stopping
            let warning = try MhypbaseManager.restore(journal)
            update(
                id, status: stopping ? .stopped : (code == 0 ? .exited : .failed),
                message: warning.nonempty ?? (stopping ? "游戏已停止" : code == 0 ? "游戏已正常退出" : "游戏进程退出码：\(code)"),
                progress: 1
            )
        } catch is CancellationError {
            await cleanupRuntimeIgnoringFailure(paths: preparedPaths, prefix: preparedPrefix, session: session)
            let warning = (try? MhypbaseManager.restore(journal)) ?? ""
            update(id, status: .stopped, message: warning.nonempty ?? "游戏已停止", progress: 1)
        } catch let error as LauncherCoreError {
            await cleanupRuntimeIgnoringFailure(paths: preparedPaths, prefix: preparedPrefix, session: session)
            let warning = (try? MhypbaseManager.restore(journal)) ?? ""
            update(id, status: .failed, message: warning.nonempty.map { "\(error.message)；\($0)" } ?? error.message)
        } catch {
            await cleanupRuntimeIgnoringFailure(paths: preparedPaths, prefix: preparedPrefix, session: session)
            let warning = (try? MhypbaseManager.restore(journal)) ?? ""
            update(id, status: .failed, message: warning.nonempty ?? "游戏启动失败，请稍后重试")
        }
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
    ) async {
        try? PrivateFilesystem.rejectSymbolicLinks(in: session.appending(path: "dns-gate"))
        try? PrivateFilesystem.removeRegularFileIfPresent(session.appending(path: "dns-gate"))
        guard let paths, let prefix else { return }
        try? await Task.detached { [prefixManager] in
            try await prefixManager.stopServer(paths: paths, prefix: prefix)
        }.value
    }

    private func register(
        _ id: String,
        after revision: Int?,
        token: UUID,
        continuation: AsyncThrowingStream<GameLaunch, Error>.Continuation
    ) {
        guard var state = states[id] else {
            continuation.finish(throwing: LauncherCoreError(code: "game_launch_missing", message: "游戏启动会话不存在"))
            return
        }
        if (state.launch.revision ?? 0) > (revision ?? -1) { continuation.yield(state.launch) }
        if Self.terminal(state.launch.status) { continuation.finish(); return }
        state.subscribers[token] = continuation
        states[id] = state
    }

    private func unregister(_ id: String, token: UUID) {
        states[id]?.subscribers[token] = nil
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
                  options: [.skipsSubdirectoryEnumeration]
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
}
