import Foundation

protocol WindowProbing: Sendable {
    func snapshot(executable: URL) async throws -> String
    func status(executable: URL, processID: Int32, snapshot: String) async throws -> Int32
}

struct FoundationWindowProbe: WindowProbing {
    func snapshot(executable: URL) async throws -> String {
        let result = try await run(executable, arguments: ["--snapshot"], capturesOutput: true)
        guard result.status == 0 else {
            throw LauncherCoreError(code: "window_probe_failed", message: "游戏窗口探针初始化失败")
        }
        return result.output.split(separator: "\n").prefix(4_096).joined(separator: ",")
    }

    func status(executable: URL, processID: Int32, snapshot: String) async throws -> Int32 {
        try await run(executable, arguments: [String(processID), snapshot], capturesOutput: false).status
    }

    private func run(
        _ executable: URL,
        arguments: [String],
        capturesOutput: Bool
    ) async throws -> (status: Int32, output: String) {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = capturesOutput ? pipe : FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            let data = capturesOutput ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
            guard data.count <= 1024 * 1024 else {
                throw LauncherCoreError(code: "window_probe_failed", message: "游戏窗口探针输出异常")
            }
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
