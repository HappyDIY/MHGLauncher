import Foundation
import Observation

struct GameJobTransferPresentation: Equatable, Sendable {
    let completedBytes: Int64
    let totalBytes: Int64
    let downloadSpeed: Int64
    let sampleID: String?

    static let empty = GameJobTransferPresentation(
        completedBytes: 0,
        totalBytes: 0,
        downloadSpeed: 0,
        sampleID: nil
    )
}

struct GameJobCountPresentation: Equatable, Sendable {
    let completed: Int64
    let total: Int64

    static let empty = GameJobCountPresentation(completed: 0, total: 0)
}

@MainActor
@Observable
final class GameJobChunkPresentation: Identifiable {
    let id: String
    private(set) var bytesDone: Int64
    private(set) var total: Int64

    init(_ value: ChunkProgress) {
        id = value.name
        bytesDone = value.bytesDone
        total = value.total
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(bytesDone) / Double(total)
    }

    func apply(_ value: ChunkProgress) {
        if bytesDone != value.bytesDone { bytesDone = value.bytesDone }
        if total != value.total { total = value.total }
    }
}

@MainActor
@Observable
final class GameJobPresentation {
    private(set) var id: String?
    private(set) var status: JobStatus = .queued
    private(set) var transfer = GameJobTransferPresentation.empty
    private(set) var counts = GameJobCountPresentation.empty
    private(set) var message = ""
    private(set) var activeChunks: [GameJobChunkPresentation] = []

    func apply(_ value: GameJob?) {
        guard let value else {
            if id != nil { id = nil }
            if !activeChunks.isEmpty { activeChunks = [] }
            return
        }
        let nextTransfer = GameJobTransferPresentation(
            completedBytes: value.completedBytes,
            totalBytes: value.totalBytes,
            downloadSpeed: value.downloadSpeed,
            sampleID: value.lastUpdate ?? value.revision.map(String.init)
        )
        let nextCounts = GameJobCountPresentation(
            completed: value.chunksCompleted,
            total: value.chunksTotal
        )
        if status != value.status { status = value.status }
        if transfer != nextTransfer { transfer = nextTransfer }
        if counts != nextCounts { counts = nextCounts }
        if message != value.message { message = value.message }
        applyChunks(value.activeChunks)
        if id != value.id { id = value.id }
    }

    private func applyChunks(_ values: [ChunkProgress]) {
        let topologyMatches = values.count == activeChunks.count
            && zip(values, activeChunks).allSatisfy { $0.name == $1.id }
        if topologyMatches {
            for (model, value) in zip(activeChunks, values) {
                model.apply(value)
            }
            return
        }
        let existing = Dictionary(uniqueKeysWithValues: activeChunks.map { ($0.id, $0) })
        let next = values.map { value in
            let model = existing[value.name] ?? GameJobChunkPresentation(value)
            model.apply(value)
            return model
        }
        activeChunks = next
    }
}
