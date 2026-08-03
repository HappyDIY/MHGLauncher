import Foundation

struct CoreProcessRequest: Sendable {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL?
    let environment: [String: String]
    let logURL: URL?
}

protocol CoreProcessRunning: Sendable {
    func run(_ request: CoreProcessRequest) async throws -> Int32
    func terminate() async
    func processIdentifier() async -> Int32?
}

actor FoundationProcessRunner: CoreProcessRunning {
    private var process: Process?

    func run(_ request: CoreProcessRequest) async throws -> Int32 {
        guard process == nil else {
            throw LauncherCoreError(code: "process_busy", message: "已有进程正在运行")
        }
        let child = Process()
        child.executableURL = request.executable
        child.arguments = request.arguments
        child.currentDirectoryURL = request.workingDirectory
        child.environment = request.environment
        child.standardInput = FileHandle.nullDevice
        var log: FileHandle?
        if let logURL = request.logURL {
            try GameFilesystem.ensureParent(of: logURL)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            try PrivateFilesystem.setPrivateFilePermissions(logURL)
            log = try FileHandle(forWritingTo: logURL)
            try log?.seekToEnd()
            child.standardOutput = log
            child.standardError = log
        } else {
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
        }
        do {
            try child.run()
            process = child
            while child.isRunning {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(150))
            }
            let status = child.terminationStatus
            process = nil
            try? log?.close()
            return status
        } catch {
            if child.isRunning { child.terminate() }
            process = nil
            try? log?.close()
            throw error
        }
    }

    func terminate() {
        process?.terminate()
    }

    func processIdentifier() -> Int32? {
        process?.isRunning == true ? process?.processIdentifier : nil
    }
}

enum LaunchArgumentParser {
    static func parse(_ input: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for character in input {
            if escaping {
                current.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { arguments.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        guard quote == nil, !escaping else {
            throw LauncherCoreError(code: "launch_arguments_invalid", message: "游戏启动参数格式无效")
        }
        if !current.isEmpty { arguments.append(current) }
        guard arguments.count <= 128, arguments.allSatisfy({ $0.utf8.count <= 4096 }) else {
            throw LauncherCoreError(code: "launch_arguments_too_large", message: "游戏启动参数过长")
        }
        return arguments
    }
}
