import Darwin
import Foundation

struct MhypbaseIntegrity: Sendable {
    let md5: String
    let sha256: String
    let size: Int64

    static let pinned = Self(
        md5: "dcb1b134e0e8bc3bb292eb41d17f5788",
        sha256: "941558c9761eadecfebe13f5aeef131e35abf11370e0eb798cbc2d1e356f04f1",
        size: 24_056_296
    )
}

struct MhypbaseJournal: Codable, Sendable {
    var schema: Int
    var generation: String
    var phase: String
    var journalPath: String
    var gameRoot: String
    var target: String
    var backup: String
    var originalExists: Bool
    var originalSHA256: String
    var originalMode: Int
    var originalDevice: UInt64
    var originalInode: UInt64
    var replacementMD5: String
}

struct MhypbaseRecoveryResult: Sendable {
    let pending: Bool
    let warnings: [String]
}

enum MhypbaseManager {
    static func isGameRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        process.arguments = ["-if", "YuanShen[.]exe"]
        process.environment = CoreProcessEnvironment.sanitizedCurrentProcess()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return true
        }
    }

    static func prepare(
        gameRoot: URL,
        source: URL,
        sessionDirectory: URL,
        integrity: MhypbaseIntegrity = .pinned
    ) async throws -> MhypbaseJournal? {
        guard GameFilesystem.regularFile(source),
              (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == integrity.size,
              try await FileDigest.md5(source) == integrity.md5,
              try FileDigest.sha256(source) == integrity.sha256 else {
            throw LauncherCoreError(code: "mhypbase_source_invalid", message: "内置 mhypbase.dll 完整性校验失败")
        }
        let target = gameRoot.appending(path: "mhypbase.dll")
        if FileManager.default.fileExists(atPath: target.path), !GameFilesystem.regularFile(target) {
            throw LauncherCoreError(code: "mhypbase_target_invalid", message: "mhypbase.dll 目标不是普通文件")
        }
        if GameFilesystem.regularFile(target), try await FileDigest.md5(target) == integrity.md5 { return nil }
        try PrivateFilesystem.ensureDirectory(sessionDirectory)
        let backup = sessionDirectory.appending(path: "mhypbase.original.dll")
        let journalURL = sessionDirectory.appending(path: "dll-journal.json")
        let originalExists = GameFilesystem.regularFile(target)
        let attributes = originalExists
            ? try FileManager.default.attributesOfItem(atPath: target.path) : [:]
        var journal = MhypbaseJournal(
            schema: 2,
            generation: "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)",
            phase: "planned",
            journalPath: journalURL.path,
            gameRoot: gameRoot.path,
            target: target.path,
            backup: backup.path,
            originalExists: originalExists,
            originalSHA256: originalExists ? try FileDigest.sha256(target) : "",
            originalMode: (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644,
            originalDevice: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
            originalInode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            replacementMD5: integrity.md5
        )
        try writeJournal(journal)
        if originalExists { try atomicCopy(source: target, destination: backup, mode: journal.originalMode) }
        try atomicCopy(source: source, destination: target, mode: journal.originalMode)
        guard try await FileDigest.md5(target) == integrity.md5 else {
            _ = try restore(journal)
            throw LauncherCoreError(code: "mhypbase_replace_failed", message: "mhypbase.dll 原子替换校验失败")
        }
        journal.phase = "installed"
        try writeJournal(journal)
        return journal
    }

    static func commit(_ journal: MhypbaseJournal?) throws -> String {
        guard let journal else { return "" }
        guard journal.schema == 2 else { return "mhypbase.dll 恢复记录版本无效" }
        try finish(journal)
        return ""
    }

    static func restore(_ journal: MhypbaseJournal?) throws -> String {
        guard let journal else { return "" }
        guard journal.schema == 2 else { return "mhypbase.dll 恢复记录版本无效" }
        let target = URL(filePath: journal.target)
        let backup = URL(filePath: journal.backup)
        if journal.originalExists, GameFilesystem.regularFile(target),
           try FileDigest.sha256(target) == journal.originalSHA256 {
            try finish(journal)
            return ""
        }
        if !journal.originalExists, !FileManager.default.fileExists(atPath: target.path) {
            try finish(journal)
            return ""
        }
        guard GameFilesystem.regularFile(target),
              try FileDigest.md5Sync(target) == journal.replacementMD5 else {
            return "mhypbase.dll 已被其他程序修改，恢复记录已保留"
        }
        if journal.originalExists {
            guard GameFilesystem.regularFile(backup),
                  try FileDigest.sha256(backup) == journal.originalSHA256 else {
                return "mhypbase.dll 原始备份校验失败，恢复记录已保留"
            }
            try atomicCopy(source: backup, destination: target, mode: journal.originalMode)
        } else {
            try PrivateFilesystem.removeRegularFileIfPresent(target)
        }
        try finish(journal)
        return ""
    }

    static func recover(dataDirectory: URL, gameRunning: Bool) -> MhypbaseRecoveryResult {
        let root = dataDirectory.appending(path: "launches")
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: root)) != nil,
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: [.skipsSubdirectoryDescendants]
              ) else { return MhypbaseRecoveryResult(pending: false, warnings: []) }
        var sessions: [URL] = []
        while let session = enumerator.nextObject() as? URL {
            guard sessions.count < 256 else {
                return MhypbaseRecoveryResult(
                    pending: true,
                    warnings: ["启动恢复记录过多，已拒绝恢复"]
                )
            }
            sessions.append(session)
        }
        let journalURLs = sessions.map { $0.appending(path: "dll-journal.json") }
            .filter(Self.exists)
        if gameRunning {
            return MhypbaseRecoveryResult(pending: !journalURLs.isEmpty, warnings: [])
        }
        var journals: [MhypbaseJournal] = []
        var warnings: [String] = []
        for session in sessions {
            let journalURL = session.appending(path: "dll-journal.json")
            guard GameFilesystem.regularFile(journalURL),
                  let values = try? journalURL.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= 1024 * 1024 else { continue }
            guard let data = try? Data(contentsOf: journalURL),
                  let journal = try? JSONDecoder.api.decode(MhypbaseJournal.self, from: data),
                  safeJournal(journal, under: session) else {
                warnings.append("启动 DLL 恢复记录无效，已拒绝执行文件操作")
                continue
            }
            journals.append(journal)
        }
        var pending = false
        for journal in journals.sorted(by: { $0.generation > $1.generation }) {
            do {
                let warning = try restore(journal)
                if !warning.isEmpty {
                    pending = true
                    warnings.append(warning)
                }
            } catch {
                pending = true
                warnings.append("启动 DLL 恢复失败")
            }
        }
        let remaining = journalURLs.contains(Self.exists)
        return MhypbaseRecoveryResult(pending: pending || remaining, warnings: warnings)
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func safeJournal(_ journal: MhypbaseJournal, under session: URL) -> Bool {
        guard journal.schema == 2,
              ["planned", "installed"].contains(journal.phase),
              URL(filePath: journal.journalPath).standardizedFileURL == session.appending(path: "dll-journal.json").standardizedFileURL,
              URL(filePath: journal.backup).standardizedFileURL == session.appending(path: "mhypbase.original.dll").standardizedFileURL,
              journal.replacementMD5.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
              (!journal.originalExists || journal.originalSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil),
              (0...0o777).contains(journal.originalMode) else { return false }
        let gameRoot = URL(filePath: journal.gameRoot).standardizedFileURL
        let target = URL(filePath: journal.target).standardizedFileURL
        let backup = URL(filePath: journal.backup).standardizedFileURL
        guard target == gameRoot.appending(path: "mhypbase.dll").standardizedFileURL,
              (try? PrivateFilesystem.rejectSymbolicLinks(in: gameRoot)) != nil,
              (try? PrivateFilesystem.rejectSymbolicLinks(in: target)) != nil,
              (try? PrivateFilesystem.rejectSymbolicLinks(in: backup)) != nil,
              let detected = GameFilesystem.detect(at: gameRoot.path),
              detected.path == (try? GameFilesystem.canonicalDirectory(gameRoot)) else { return false }
        return !target.path.hasPrefix(session.path + "/")
    }

    private static func writeJournal(_ journal: MhypbaseJournal) throws {
        try GameFilesystem.writePrivate(
            JSONEncoder.api.encode(journal), to: URL(filePath: journal.journalPath)
        )
    }

    private static func atomicCopy(source: URL, destination: URL, mode: Int) throws {
        guard GameFilesystem.regularFile(source) else {
            throw LauncherCoreError(code: "mhypbase_file_invalid", message: "mhypbase.dll 文件无效")
        }
        try GameFilesystem.ensureParent(of: destination)
        let temporary = URL(filePath: destination.path + ".\(UUID().uuidString).tmp")
        try PrivateFilesystem.rejectSymbolicLinks(in: destination)
        try PrivateFilesystem.rejectSymbolicLinks(in: temporary)
        defer { try? PrivateFilesystem.removeRegularFileIfPresent(temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard GameFilesystem.regularFile(destination) else {
                throw LauncherCoreError(code: "mhypbase_target_invalid", message: "mhypbase.dll 目标不是普通文件")
            }
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    private static func finish(_ journal: MhypbaseJournal) throws {
        let backup = URL(filePath: journal.backup)
        let journalURL = URL(filePath: journal.journalPath)
        guard (try? PrivateFilesystem.rejectSymbolicLinks(in: backup)) != nil,
              (try? PrivateFilesystem.rejectSymbolicLinks(in: journalURL)) != nil else { return }
        try PrivateFilesystem.removeRegularFileIfPresent(backup)
        try PrivateFilesystem.removeRegularFileIfPresent(journalURL)
    }

}
