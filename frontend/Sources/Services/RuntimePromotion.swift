import Foundation

struct RuntimePromotionRecord: Codable, Equatable {
    let stage: String
    let destination: String
    let backup: String
}

enum RuntimePromotion {
    static func promote(stage: URL, destination: URL, fileManager: FileManager) throws {
        let parent = destination.deletingLastPathComponent()
        let backup = parent.appending(path: ".\(destination.lastPathComponent).backup")
        let journal = parent.appending(path: ".\(destination.lastPathComponent).promotion.json")
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try recover(journal: journal, fileManager: fileManager)
        let record = RuntimePromotionRecord(
            stage: stage.path,
            destination: destination.path,
            backup: backup.path
        )
        try JSONEncoder().encode(record).write(to: journal, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: stage, to: destination)
            try? fileManager.removeItem(at: backup)
            try fileManager.removeItem(at: journal)
        } catch {
            try? fileManager.removeItem(at: destination)
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            try? fileManager.removeItem(at: journal)
            throw error
        }
    }

    static func recover(journal: URL, fileManager: FileManager = .default) throws {
        guard let data = try? Data(contentsOf: journal),
              let record = try? JSONDecoder().decode(RuntimePromotionRecord.self, from: data) else {
            return
        }
        let stage = URL(fileURLWithPath: record.stage)
        let destination = URL(fileURLWithPath: record.destination)
        let backup = URL(fileURLWithPath: record.backup)
        if fileManager.fileExists(atPath: backup.path) {
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: backup, to: destination)
        }
        try? fileManager.removeItem(at: stage)
        try? fileManager.removeItem(at: journal)
    }
}
