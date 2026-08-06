import Darwin
import Foundation

struct RuntimeDirectoryIdentity: Codable, Equatable {
    let volume: UInt64
    let file: UInt64
}

struct RuntimePromotionRecord: Codable, Equatable {
    let schemaVersion: Int
    let stage: String
    let destination: String
    let backup: String
    let stageIdentity: RuntimeDirectoryIdentity
    let destinationIdentity: RuntimeDirectoryIdentity?
}

enum RuntimePromotion {
    static func promote(stage: URL, destination: URL, fileManager: FileManager) throws {
        let parent = destination.deletingLastPathComponent().standardizedFileURL
        guard stage.deletingLastPathComponent().standardizedFileURL == parent,
              !destination.lastPathComponent.isEmpty else {
            throw RuntimeInstallError.unsafePromotion
        }
        let backup = parent.appending(path: ".\(destination.lastPathComponent).backup")
        let journal = parent.appending(path: ".\(destination.lastPathComponent).promotion.json")
        try secureDirectory(parent)
        try recover(journal: journal, fileManager: fileManager)
        try securePath(stage)
        try secureTree(stage)
        try securePath(destination)
        if exists(destination) { try secureTree(destination) }
        try securePath(backup)
        try securePath(journal)
        let stageIdentity = try identity(of: stage, fileManager: fileManager)
        let destinationIdentity = exists(destination) ? try identity(of: destination, fileManager: fileManager) : nil
        guard !exists(backup) else { throw RuntimeInstallError.unsafePromotion }
        let record = RuntimePromotionRecord(
            schemaVersion: 1,
            stage: stage.path,
            destination: destination.path,
            backup: backup.path,
            stageIdentity: stageIdentity,
            destinationIdentity: destinationIdentity
        )
        try GameFilesystem.writePrivate(try JSONEncoder().encode(record), to: journal)
        var backedUp = false
        var promoted = false
        if exists(destination) {
            try fileManager.moveItem(at: destination, to: backup)
            backedUp = true
        }
        do {
            try fileManager.moveItem(at: stage, to: destination)
            promoted = true
            guard matches(destination, stageIdentity, fileManager: fileManager) else {
                throw RuntimeInstallError.unsafePromotion
            }
        } catch {
            if promoted && matches(destination, stageIdentity, fileManager: fileManager) {
                try? removeDirectory(destination, fileManager: fileManager)
            }
            if backedUp && !exists(destination)
                && matches(backup, destinationIdentity, fileManager: fileManager) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            if !exists(backup) {
                secureRemove(journal, fileManager: fileManager)
            }
            throw error
        }
        if exists(backup) {
            guard matches(backup, destinationIdentity, fileManager: fileManager) else {
                throw RuntimeInstallError.unsafePromotion
            }
            try removeDirectory(backup, fileManager: fileManager)
        }
        try secureRemove(journal, fileManager: fileManager)
    }

    static func recover(journal: URL, fileManager: FileManager = .default) throws {
        try securePath(journal)
        guard exists(journal) else {
            return
        }
        guard GameFilesystem.regularFile(journal),
              let values = try? journal.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= 1024 * 1024,
              let data = try? Data(contentsOf: journal, options: .mappedIfSafe) else {
            throw RuntimeInstallError.unsafePromotion
        }
        let record = try validatedRecord(data: data, journal: journal)
        let stage = URL(fileURLWithPath: record.stage)
        let destination = URL(fileURLWithPath: record.destination)
        let backup = URL(fileURLWithPath: record.backup)
        try securePath(stage)
        try securePath(destination)
        try securePath(backup)
        if exists(stage) { try secureTree(stage) }
        if exists(destination) { try secureTree(destination) }
        if exists(backup) { try secureTree(backup) }
        if exists(backup) {
            guard matches(backup, record.destinationIdentity, fileManager: fileManager) else {
                throw RuntimeInstallError.unsafePromotion
            }
            if matches(destination, record.stageIdentity, fileManager: fileManager),
               !exists(stage) {
                try removeDirectory(backup, fileManager: fileManager)
            } else if !exists(destination) {
                try fileManager.moveItem(at: backup, to: destination)
            } else {
                throw RuntimeInstallError.unsafePromotion
            }
        } else if !exists(destination), exists(stage) {
            guard matches(stage, record.stageIdentity, fileManager: fileManager) else {
                throw RuntimeInstallError.unsafePromotion
            }
            try fileManager.moveItem(at: stage, to: destination)
        }
        if matches(destination, record.destinationIdentity, fileManager: fileManager)
            || matches(destination, record.stageIdentity, fileManager: fileManager) {
            if exists(stage) { try? removeDirectory(stage, fileManager: fileManager) }
        } else if exists(destination) {
            throw RuntimeInstallError.unsafePromotion
        }
        guard exists(destination) else { throw RuntimeInstallError.unsafePromotion }
        secureRemove(journal, fileManager: fileManager)
    }

    private static func validatedRecord(data: Data, journal: URL) throws -> RuntimePromotionRecord {
        let record = try JSONDecoder().decode(RuntimePromotionRecord.self, from: data)
        let parent = journal.deletingLastPathComponent().standardizedFileURL
        let name = journal.lastPathComponent
        let prefix = "."
        let suffix = ".promotion.json"
        guard record.schemaVersion == 1,
              name.hasPrefix(prefix), name.hasSuffix(suffix),
              name.count > prefix.count + suffix.count else {
            throw RuntimeInstallError.unsafePromotion
        }
        let tag = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        let expectedDestination = parent.appending(path: tag).standardizedFileURL
        let expectedBackup = parent.appending(path: ".\(tag).backup").standardizedFileURL
        let stage = URL(fileURLWithPath: record.stage).standardizedFileURL
        let destination = URL(fileURLWithPath: record.destination).standardizedFileURL
        guard !tag.isEmpty, tag != ".", tag != "..", !tag.contains("/"),
              destination == expectedDestination,
              destination.deletingLastPathComponent() == parent,
              URL(fileURLWithPath: record.backup).standardizedFileURL == expectedBackup,
              stage.deletingLastPathComponent() == parent,
              stage.lastPathComponent.hasPrefix(".\(tag)-") else {
            throw RuntimeInstallError.unsafePromotion
        }
        return record
    }

    private static func identity(
        of url: URL,
        fileManager: FileManager
    ) throws -> RuntimeDirectoryIdentity {
        _ = fileManager
        try securePath(url)
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR else {
            throw RuntimeInstallError.unsafePromotion
        }
        return RuntimeDirectoryIdentity(
            volume: UInt64(info.st_dev),
            file: UInt64(info.st_ino)
        )
    }

    private static func matches(
        _ url: URL,
        _ expected: RuntimeDirectoryIdentity?,
        fileManager: FileManager
    ) -> Bool {
        guard let expected else { return false }
        return (try? identity(of: url, fileManager: fileManager)) == expected
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func secureDirectory(_ url: URL) throws {
        do {
            try PrivateFilesystem.ensureDirectory(url)
        } catch {
            throw RuntimeInstallError.unsafePromotion
        }
    }

    private static func securePath(_ url: URL) throws {
        do {
            try PrivateFilesystem.rejectSymbolicLinks(in: url)
        } catch {
            throw RuntimeInstallError.unsafePromotion
        }
    }

    private static func secureTree(_ url: URL) throws {
        do {
            try RuntimeInstallLedger.validateTree(at: url)
        } catch {
            throw RuntimeInstallError.unsafePromotion
        }
    }

    private static func removeDirectory(_ url: URL, fileManager: FileManager) throws {
        try secureTree(url)
        guard exists(url) else { return }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw RuntimeInstallError.unsafePromotion
        }
        try fileManager.removeItem(at: url)
    }

    private static func secureRemove(_ url: URL, fileManager: FileManager) {
        guard GameFilesystem.regularFile(url) else { return }
        _ = fileManager
        try? PrivateFilesystem.removeRegularFileIfPresent(url)
    }
}
