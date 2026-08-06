import Darwin
import Foundation

enum GameActivation {
    private struct Identity: Codable, Equatable {
        let volume: UInt64
        let file: UInt64
    }

    private struct Journal: Codable {
        let schema: Int
        let stage: String
        let destination: String
        let backup: String
        let stageIdentity: Identity
        let destinationIdentity: Identity?
    }

    static func activate(stage: URL, destination: URL, backup: URL) throws {
        let parent = destination.deletingLastPathComponent().standardizedFileURL
        guard stage.deletingLastPathComponent().standardizedFileURL == parent,
              backup.deletingLastPathComponent().standardizedFileURL == parent,
              !destination.lastPathComponent.isEmpty else {
            throw unsafe()
        }
        try PrivateFilesystem.ensureDirectory(parent)
        try recover(destination: destination)
        try secureDirectory(stage)
        try PrivateFilesystem.rejectSymbolicLinksRecursively(in: stage)
        try securePath(destination)
        if exists(destination) {
            try PrivateFilesystem.rejectSymbolicLinksRecursively(in: destination)
        }
        try securePath(backup)
        let journal = journalURL(for: destination)
        try securePath(journal)
        guard !exists(backup), !exists(journal) else {
            throw unsafe()
        }

        let stageIdentity = try identity(of: stage)
        let destinationIdentity: Identity?
        if exists(destination) {
            destinationIdentity = try identity(of: destination)
        } else {
            destinationIdentity = nil
        }
        let record = Journal(
            schema: 1,
            stage: stage.standardizedFileURL.path,
            destination: destination.standardizedFileURL.path,
            backup: backup.standardizedFileURL.path,
            stageIdentity: stageIdentity,
            destinationIdentity: destinationIdentity
        )
        try GameFilesystem.writePrivate(try JSONEncoder().encode(record), to: journal)

        var backedUp = false
        var promoted = false
        do {
            if destinationIdentity != nil {
                try FileManager.default.moveItem(at: destination, to: backup)
                backedUp = true
                guard matches(backup, destinationIdentity) else { throw unsafe() }
            }
            try FileManager.default.moveItem(at: stage, to: destination)
            promoted = true
            guard matches(destination, stageIdentity) else { throw unsafe() }
            if backedUp {
                try PrivateFilesystem.removeDirectoryIfPresent(backup)
                backedUp = false
            }
            try removeJournal(journal)
        } catch {
            if promoted {
                // 新目录已经提交；若旧目录仍在，保留记录交给下次启动清理。
                if !exists(backup), matches(destination, stageIdentity) {
                    try? removeJournal(journal)
                }
                throw error
            }
            if backedUp, !exists(destination), matches(backup, destinationIdentity) {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            if !exists(backup) { try? removeJournal(journal) }
            throw error
        }
    }

    static func recover(destination: URL) throws {
        let journal = journalURL(for: destination)
        try securePath(journal)
        guard exists(journal) else { return }
        guard GameFilesystem.regularFile(journal),
              let values = try? journal.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 1024 * 1024,
              let data = try? Data(contentsOf: journal),
              let record = try? JSONDecoder().decode(Journal.self, from: data) else {
            throw unsafe()
        }
        try validate(record, journal: journal)
        let stage = URL(filePath: record.stage)
        let target = URL(filePath: record.destination)
        let backup = URL(filePath: record.backup)
        try securePath(stage)
        try securePath(target)
        try securePath(backup)
        if exists(stage) {
            try PrivateFilesystem.rejectSymbolicLinksRecursively(in: stage)
        }
        if exists(target) {
            try PrivateFilesystem.rejectSymbolicLinksRecursively(in: target)
        }
        if exists(backup) {
            try PrivateFilesystem.rejectSymbolicLinksRecursively(in: backup)
        }

        if exists(backup) {
            guard matches(backup, record.destinationIdentity) else { throw unsafe() }
            if matches(target, record.stageIdentity), !exists(stage) {
                try PrivateFilesystem.removeDirectoryIfPresent(backup)
            } else if !exists(target) {
                try FileManager.default.moveItem(at: backup, to: target)
                if exists(stage) {
                    guard matches(stage, record.stageIdentity) else { throw unsafe() }
                    try PrivateFilesystem.removeDirectoryIfPresent(stage)
                }
            } else {
                throw unsafe()
            }
        } else if !exists(target), exists(stage) {
            guard matches(stage, record.stageIdentity) else { throw unsafe() }
            try FileManager.default.moveItem(at: stage, to: target)
        }

        if exists(target) {
            guard matches(target, record.destinationIdentity) || matches(target, record.stageIdentity) else {
                throw unsafe()
            }
        }
        if exists(stage) {
            guard matches(stage, record.stageIdentity) else { throw unsafe() }
            try PrivateFilesystem.removeDirectoryIfPresent(stage)
        }
        guard exists(target) else { throw unsafe() }
        try removeJournal(journal)
    }

    private static func journalURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).mhg-activation.json")
    }

    private static func validate(_ record: Journal, journal: URL) throws {
        let destination = URL(filePath: record.destination).standardizedFileURL
        let parent = journal.deletingLastPathComponent().standardizedFileURL
        let expected = parent.appending(path: destination.lastPathComponent).standardizedFileURL
        let stage = URL(filePath: record.stage).standardizedFileURL
        let backup = URL(filePath: record.backup).standardizedFileURL
        guard record.schema == 1,
              !destination.lastPathComponent.isEmpty,
              destination.deletingLastPathComponent() == parent,
              destination.lastPathComponent != ".",
              destination.lastPathComponent != "..",
              !destination.lastPathComponent.contains("/"),
              destination == expected,
              stage.deletingLastPathComponent() == parent,
              stage.lastPathComponent.hasPrefix(".\(destination.lastPathComponent).mhg-staging-"),
              backup.deletingLastPathComponent() == parent,
              backup.lastPathComponent.hasPrefix(".\(destination.lastPathComponent).mhg-backup-") else {
            throw unsafe()
        }
    }

    private static func identity(of url: URL) throws -> Identity {
        try secureDirectory(url)
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw unsafe() }
        return Identity(volume: UInt64(info.st_dev), file: UInt64(info.st_ino))
    }

    private static func matches(_ url: URL, _ expected: Identity?) -> Bool {
        guard let expected else { return false }
        return (try? identity(of: url)) == expected
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func secureDirectory(_ url: URL) throws {
        try PrivateFilesystem.rejectSymbolicLinks(in: url)
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw unsafe() }
    }

    private static func securePath(_ url: URL) throws {
        try PrivateFilesystem.rejectSymbolicLinks(in: url)
    }

    private static func removeJournal(_ url: URL) throws {
        guard GameFilesystem.regularFile(url) else { throw unsafe() }
        try PrivateFilesystem.removeRegularFileIfPresent(url)
    }

    private static func unsafe() -> LauncherCoreError {
        LauncherCoreError(code: "game_activation_unsafe", message: "游戏目录恢复记录不安全，已拒绝文件操作")
    }
}
