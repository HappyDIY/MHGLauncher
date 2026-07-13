import Foundation
import Observation

@MainActor
@Observable
final class BackendProcess {
    private(set) var client: APIClient?
    private(set) var errorMessage: String?
    private(set) var isStarting = false
    private var process: Process?
    private var socketPath: String?
    private var drains: [ProcessPipeDrain] = []
    private var isStopping = false

    var isReady: Bool { client != nil }

    func start(runtime: InstalledRuntime) async {
        guard process == nil, !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            let token = UUID().uuidString
            let socketPath = Self.makeSocketPath()
            let pipe = Pipe()
            let errorPipe = Pipe()
            let process = Process()
            process.executableURL = runtime.nodeURL
            process.arguments = ["build/server.js"]
            process.currentDirectoryURL = runtime.backendAppURL
            process.standardOutput = pipe
            process.standardError = errorPipe
            process.environment = Self.environment(
                token: token,
                socketPath: socketPath,
                runtime: runtime
            )
            let outputDrain = ProcessPipeDrain(handle: pipe.fileHandleForReading, capturesReady: true)
            let errorDrain = ProcessPipeDrain(handle: errorPipe.fileHandleForReading, capturesReady: false)
            drains = [outputDrain, errorDrain]
            process.terminationHandler = { [weak self] finished in
                Task { @MainActor in self?.processExited(finished) }
            }
            try process.run()
            self.process = process
            let readyPath = try await outputDrain.readyPath()
            guard readyPath == socketPath else { throw CocoaError(.fileReadCorruptFile) }
            self.socketPath = socketPath
            client = APIClient(socketPath: socketPath, token: token)
        } catch {
            process?.terminate()
            for drain in drains { drain.close() }
            drains.removeAll()
            process = nil
            client = nil
            errorMessage = Self.startupFailureMessage
        }
    }

    func stop() async {
        guard let process else { client = nil; return }
        isStopping = true; process.terminate(); client = nil
        let deadline = ContinuousClock.now + .seconds(5)
        while process.isRunning && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        if process.isRunning {
            errorMessage = "本地服务正在等待游戏退出并恢复临时文件"
            return
        }
        cleanup(process)
    }

    func useClient(_ client: APIClient) {
        self.client = client
        errorMessage = nil
    }

    nonisolated static func environment(
        token: String,
        socketPath: String,
        runtime: InstalledRuntime,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var values = base
        values["MHG_API_TOKEN"] = token
        values["MHG_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        values["MHG_SOCKET_PATH"] = socketPath
        values["MHG_DATA_DIR"] = base["MHG_DATA_DIR"] ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MHGLauncher").path
        values["NODE_ENV"] = "production"
        values["MHG_HPATCHZ"] = runtime.hpatchzURL.path
        values["MHG_RUNTIME_ROOT"] = runtime.gameRuntimeURL.path
        return values
    }

    nonisolated static func readSocketPath(from handle: FileHandle) async throws -> String {
        let drain = ProcessPipeDrain(handle: handle, capturesReady: true)
        defer { drain.close() }
        return try await drain.readyPath()
    }

    nonisolated static func makeSocketPath() -> String {
        "/tmp/mhg-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8)).sock"
    }

    nonisolated static let startupFailureMessage = "本地服务启动失败，请检查运行时安装后重试"

    private func processExited(_ finished: Process) {
        guard process === finished else { return }
        let unexpected = !isStopping && finished.terminationStatus != 0
        cleanup(finished)
        if unexpected { errorMessage = Self.startupFailureMessage }
    }

    private func cleanup(_ finished: Process) {
        guard process === finished else { return }
        for drain in drains { drain.close() }
        drains.removeAll(); process = nil; socketPath = nil; client = nil; isStopping = false
    }
}
