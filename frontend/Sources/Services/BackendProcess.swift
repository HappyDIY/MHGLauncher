import Foundation
import Observation

@MainActor
@Observable
final class BackendProcess {
    private(set) var client: APIClient?
    private(set) var errorMessage: String?
    private(set) var isStarting = false
    private var process: Process?

    var isReady: Bool { client != nil }

    func start() async {
        guard process == nil, !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            let token = UUID().uuidString
            let executable = try executableURL()
            let pipe = Pipe()
            let errorPipe = Pipe()
            let process = Process()
            process.executableURL = executable
            process.standardOutput = pipe
            process.standardError = errorPipe
            process.environment = environment(token: token)
            try process.run()
            self.process = process
            let port = try await Self.readPort(from: pipe.fileHandleForReading)
            client = APIClient(
                baseURL: URL(string: "http://127.0.0.1:\(port)")!,
                token: token
            )
        } catch {
            process?.terminate()
            process = nil
            client = nil
            errorMessage = "本地服务启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        client = nil
    }

    private func executableURL() throws -> URL {
        if let url = Bundle.main.url(
            forResource: "MHGLauncherBackend",
            withExtension: nil,
            subdirectory: "Backend/MHGLauncherBackend"
        ) {
            return url
        }
        if let override = ProcessInfo.processInfo.environment["MHG_BACKEND_EXECUTABLE"] {
            return URL(fileURLWithPath: override)
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func environment(token: String) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["MHG_API_TOKEN"] = token
        values["MHG_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        values["MHG_DATA_DIR"] = FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MHGLauncher")
            .path
        return values
    }

    nonisolated static func readPort(from handle: FileHandle) async throws -> Int {
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
                      let port = payload["port"] as? Int else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return port
            }
            throw CocoaError(.fileReadTooLarge)
        }.value
    }
}
