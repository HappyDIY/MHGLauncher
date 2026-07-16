import Testing
@testable import MHGLauncher

@MainActor
@Suite("游戏任务增量展示模型")
struct GameJobPresentationTests {
    @Test("数值更新原位复用分块模型")
    func numericUpdatesReuseChunkModels() {
        let presentation = GameJobPresentation()
        presentation.apply(job(bytes: 10, chunks: [chunk("a", 3), chunk("b", 4)]))
        let original = presentation.activeChunks

        presentation.apply(job(bytes: 20, chunks: [chunk("a", 8), chunk("b", 9)]))

        #expect(presentation.activeChunks[0] === original[0])
        #expect(presentation.activeChunks[1] === original[1])
        #expect(original[0].bytesDone == 8)
        #expect(presentation.progress.completedBytes == 20)
    }

    @Test("二万次数值事件不增长展示拓扑")
    func highFrequencyUpdatesKeepStableTopology() {
        let presentation = GameJobPresentation()
        presentation.apply(job(bytes: 0, chunks: [chunk("a", 0), chunk("b", 0)]))
        let original = presentation.activeChunks

        for value in 1...20_000 {
            let bytes = Int64(value % 1_000)
            presentation.apply(job(
                bytes: bytes,
                chunks: [chunk("a", bytes % 100), chunk("b", (bytes + 1) % 100)]
            ))
        }

        #expect(presentation.activeChunks.count == 2)
        #expect(presentation.activeChunks[0] === original[0])
        #expect(presentation.activeChunks[1] === original[1])
    }

    @Test("结构更新仅替换变化的分块")
    func topologyUpdatesReuseRemainingChunks() {
        let presentation = GameJobPresentation()
        presentation.apply(job(bytes: 10, chunks: [chunk("a", 3), chunk("b", 4)]))
        let retained = presentation.activeChunks[1]

        presentation.apply(job(bytes: 20, chunks: [chunk("b", 9), chunk("c", 1)]))

        #expect(presentation.activeChunks.map(\.id) == ["b", "c"])
        #expect(presentation.activeChunks[0] === retained)
    }

    @Test("任务结束后立即释放分块引用")
    func clearingJobReleasesTopology() {
        let presentation = GameJobPresentation()
        presentation.apply(job(bytes: 10, chunks: [chunk("a", 3)]))

        presentation.apply(nil)

        #expect(presentation.id == nil)
        #expect(presentation.activeChunks.isEmpty)
    }

    private func chunk(_ name: String, _ bytes: Int64) -> ChunkProgress {
        ChunkProgress(name: name, bytesDone: bytes, total: 100)
    }

    private func job(bytes: Int64, chunks: [ChunkProgress]) -> GameJob {
        GameJob(
            id: "job", kind: .install, status: .running,
            completedBytes: bytes, totalBytes: 1_000, message: "",
            downloadSpeed: 100, chunksCompleted: 0, chunksTotal: 10,
            activeChunks: chunks, lastUpdate: "\(bytes)", revision: Int(bytes)
        )
    }
}
