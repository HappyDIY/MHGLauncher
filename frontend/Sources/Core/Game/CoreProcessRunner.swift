import Darwin
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

enum CoreProcessEnvironment {
    static func withoutDynamicLoaderInjection(_ environment: [String: String]) -> [String: String] {
        environment.filter { key, _ in
            !key.hasPrefix("DYLD_") && !key.hasPrefix("LD_")
        }
    }

    static func sanitizedCurrentProcess() -> [String: String] {
        let allowedKeys = [
            "HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "TMP", "TEMP",
            "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
            "__CF_USER_TEXT_ENCODING", "LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES"
        ]
        return withoutDynamicLoaderInjection(
            ProcessInfo.processInfo.environment.filter { allowedKeys.contains($0.key) }
        )
    }
}

actor FoundationProcessRunner: CoreProcessRunning {
    private static let maximumLogBytes = 64 * 1024 * 1024
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
        var logSink: BoundedProcessLog?
        if let logURL = request.logURL {
            try GameFilesystem.ensureParent(of: logURL)
            try PrivateFilesystem.rejectSymbolicLinks(in: logURL)
            let opened = try Self.openLogFile(logURL, maximumBytes: Self.maximumLogBytes)
            log = opened.handle
            logSink = BoundedProcessLog(
                output: opened.handle,
                initialBytes: opened.size,
                maximumBytes: Self.maximumLogBytes
            )
            child.standardOutput = logSink?.pipe.fileHandleForWriting
            child.standardError = logSink?.pipe.fileHandleForWriting
        } else {
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
        }
        do {
            try child.run()
            logSink?.closeWriter()
            process = child
            while child.isRunning {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(150))
            }
            let status = child.terminationStatus
            process = nil
            logSink?.finish()
            try? log?.close()
            return status
        } catch {
            if child.isRunning {
                child.terminate()
                child.waitUntilExit()
            }
            logSink?.closeWriter()
            logSink?.finish()
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

    private static func openLogFile(
        _ url: URL,
        maximumBytes: Int
    ) throws -> (handle: FileHandle, size: Int) {
        let descriptor = open(
            url.path,
            O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw LauncherCoreError(code: "process_log_failed", message: "无法创建进程日志文件")
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw LauncherCoreError(code: "process_log_failed", message: "进程日志路径不是普通文件")
        }
        var size = Int(info.st_size)
        if size > maximumBytes {
            guard ftruncate(descriptor, 0) == 0 else {
                close(descriptor)
                throw LauncherCoreError(code: "process_log_failed", message: "无法截断进程日志文件")
            }
            size = 0
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            close(descriptor)
            throw LauncherCoreError(code: "process_log_failed", message: "无法设置进程日志权限")
        }
        return (
            FileHandle(fileDescriptor: descriptor, closeOnDealloc: true),
            size
        )
    }
}

private final class BoundedProcessLog: @unchecked Sendable {
    let pipe = Pipe()

    private let output: FileHandle
    private let maximumBytes: Int
    private var written: Int
    private let readHandle: FileHandle
    private let readLock = NSLock()
    private let stateLock = NSLock()
    private var finished = false

    init(output: FileHandle, initialBytes: Int, maximumBytes: Int) {
        self.output = output
        self.written = min(max(initialBytes, 0), maximumBytes)
        self.maximumBytes = maximumBytes
        readHandle = pipe.fileHandleForReading
        readHandle.readabilityHandler = { [weak self] handle in
            self?.consumeAvailable(from: handle)
        }
    }

    func closeWriter() {
        try? pipe.fileHandleForWriting.close()
    }

    func finish() {
        readHandle.readabilityHandler = nil
        while true {
            let chunk = readAvailable(from: readHandle)
            if chunk.isEmpty { break }
            consume(chunk)
        }
        try? readHandle.close()
        stateLock.lock()
        finished = true
        stateLock.unlock()
    }

    private func consumeAvailable(from handle: FileHandle) {
        let chunk = readAvailable(from: handle)
        if !chunk.isEmpty { consume(chunk) }
    }

    private func readAvailable(from handle: FileHandle) -> Data {
        readLock.lock()
        defer { readLock.unlock() }
        return handle.availableData
    }

    private func consume(_ chunk: Data) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !finished, written < maximumBytes else { return }
        let amount = min(maximumBytes - written, chunk.count)
        guard amount > 0 else { return }
        do {
            try output.write(contentsOf: Data(chunk.prefix(amount)))
            written += amount
        } catch {
            written = maximumBytes
        }
    }
}

enum LaunchArgumentParser {
    static func parse(_ input: String) throws -> [String] {
        guard input.utf8.count <= 512 * 1024,
              !input.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw LauncherCoreError(code: "launch_arguments_too_large", message: "游戏启动参数过长")
        }
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
