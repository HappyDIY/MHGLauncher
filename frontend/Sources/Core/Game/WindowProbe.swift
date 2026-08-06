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
        let value = result.output.split(whereSeparator: \.isNewline).prefix(4_096).joined(separator: ",")
        guard value.utf8.count <= 128 * 1024,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw LauncherCoreError(code: "window_probe_output_invalid", message: "游戏窗口探针输出无效")
        }
        return value
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
            process.environment = CoreProcessEnvironment.sanitizedCurrentProcess()
            process.standardInput = FileHandle.nullDevice
            let capture = capturesOutput ? BoundedProcessCapture(limit: 1024 * 1024) : nil
            process.standardOutput = capture?.pipe.fileHandleForWriting ?? FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    try process.run()
                    process.waitUntilExit()
                    try Task.checkCancellation()
                } onCancel: {
                    if process.isRunning { process.terminate() }
                }
                capture?.closeWriter()
                let data = try capture?.finish() ?? Data()
                return (process.terminationStatus, String(decoding: data, as: UTF8.self))
            } catch {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                capture?.closeWriter()
                _ = try? capture?.finish()
                throw error
            }
        }.value
    }
}
