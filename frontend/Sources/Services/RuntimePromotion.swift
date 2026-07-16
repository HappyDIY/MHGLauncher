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
        let parent = destination.deletingLastPathComponent()
        let backup = parent.appending(path: ".\(destination.lastPathComponent).backup")
        let journal = parent.appending(path: ".\(destination.lastPathComponent).promotion.json")
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try recover(journal: journal, fileManager: fileManager)
        let stageIdentity = try identity(of: stage, fileManager: fileManager)
        let destinationIdentity = try? identity(of: destination, fileManager: fileManager)
        let record = RuntimePromotionRecord(
            schemaVersion: 1,
            stage: stage.path,
            destination: destination.path,
            backup: backup.path,
            stageIdentity: stageIdentity,
            destinationIdentity: destinationIdentity
        )
        try JSONEncoder().encode(record).write(to: journal, options: .atomic)
        var backedUp = false
        var promoted = false
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: backup)
            backedUp = true
        }
        do {
            try fileManager.moveItem(at: stage, to: destination)
            promoted = true
        } catch {
            if promoted && matches(destination, stageIdentity, fileManager: fileManager) {
                try? fileManager.removeItem(at: destination)
            }
            if backedUp && !fileManager.fileExists(atPath: destination.path)
                && matches(backup, destinationIdentity, fileManager: fileManager) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            if !fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: journal)
            }
            throw error
        }
        if fileManager.fileExists(atPath: backup.path) {
            guard matches(backup, destinationIdentity, fileManager: fileManager) else {
                throw RuntimeInstallError.unsafePromotion
            }
            try fileManager.removeItem(at: backup)
        }
        try fileManager.removeItem(at: journal)
    }

    static func recover(journal: URL, fileManager: FileManager = .default) throws {
        guard let data = try? Data(contentsOf: journal) else {
            return
        }
        let record = try validatedRecord(data: data, journal: journal)
        let stage = URL(fileURLWithPath: record.stage)
        let destination = URL(fileURLWithPath: record.destination)
        let backup = URL(fileURLWithPath: record.backup)
        if fileManager.fileExists(atPath: backup.path) {
            guard matches(backup, record.destinationIdentity, fileManager: fileManager) else {
                throw RuntimeInstallError.unsafePromotion
            }
            if matches(destination, record.stageIdentity, fileManager: fileManager),
               !fileManager.fileExists(atPath: stage.path) {
                try fileManager.removeItem(at: backup)
            } else if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: backup, to: destination)
            } else {
                throw RuntimeInstallError.unsafePromotion
            }
        } else if !fileManager.fileExists(atPath: destination.path),
                  fileManager.fileExists(atPath: stage.path) {
            guard matches(stage, record.stageIdentity, fileManager: fileManager) else {
                throw RuntimeInstallError.unsafePromotion
            }
            try fileManager.moveItem(at: stage, to: destination)
        }
        if matches(destination, record.destinationIdentity, fileManager: fileManager)
            || matches(destination, record.stageIdentity, fileManager: fileManager) {
            try? fileManager.removeItem(at: stage)
        } else if fileManager.fileExists(atPath: destination.path) {
            throw RuntimeInstallError.unsafePromotion
        }
        try? fileManager.removeItem(at: journal)
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
        guard URL(fileURLWithPath: record.destination).standardizedFileURL == expectedDestination,
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
        let values = try fileManager.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeDirectory,
              let volume = values[.systemNumber] as? NSNumber,
              let file = values[.systemFileNumber] as? NSNumber else {
            throw RuntimeInstallError.unsafePromotion
        }
        return RuntimeDirectoryIdentity(
            volume: volume.uint64Value,
            file: file.uint64Value
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
}
