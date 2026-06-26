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
            try process.run()
            self.process = process
            let readyPath = try await Self.readSocketPath(from: pipe.fileHandleForReading)
            guard readyPath == socketPath else { throw CocoaError(.fileReadCorruptFile) }
            self.socketPath = socketPath
            client = APIClient(socketPath: socketPath, token: token)
        } catch {
            process?.terminate()
            process = nil
            client = nil
            errorMessage = "本地服务启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        process?.terminate()
        if let socketPath { try? FileManager.default.removeItem(atPath: socketPath) }
        process = nil
        socketPath = nil
        client = nil
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
        try await Task.detached {
            var data = Data()
            while data.count <= 16_384 {
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                data.append(chunk)
                guard let newline = data.firstIndex(of: 0x0A) else { continue }
                let line = data[..<newline]
                let object = try JSONSerialization.jsonObject(with: Data(line))
                guard let payload = object as? [String: Any],
                      payload["event"] as? String == "ready",
                      let socketPath = payload["socket_path"] as? String else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return socketPath
            }
            throw CocoaError(.fileReadTooLarge)
        }.value
    }

    nonisolated static func makeSocketPath() -> String {
        "/tmp/mhg-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8)).sock"
    }
}
