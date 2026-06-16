import Testing
@testable import MHGLauncher

@Suite("游戏任务模型")
struct GameModelTests {
    @Test("计算下载进度")
    func progress() {
        let job = GameJob(
            id: "job",
            kind: .install,
            status: .running,
            completedBytes: 25,
            totalBytes: 100,
            message: "",
            downloadSpeed: 0,
            chunksCompleted: 0,
            chunksTotal: 0,
            activeChunks: [],
            lastUpdate: nil
        )
        #expect(job.progress == 0.25)
    }

    @Test("空任务进度为零")
    func emptyProgress() {
        let job = GameJob(
            id: "job",
            kind: .verify,
            status: .queued,
            completedBytes: 0,
            totalBytes: 0,
            message: "",
            downloadSpeed: 0,
            chunksCompleted: 0,
            chunksTotal: 0,
            activeChunks: [],
            lastUpdate: nil
        )
        #expect(job.progress == 0)
    }

    @Test("分块进度计算")
    func chunkProgress() {
        let chunk = ChunkProgress(name: "chunk_01.bin", bytesDone: 50, total: 100)
        #expect(chunk.progress == 0.5)
    }

    @Test("空分块进度为零")
    func chunkProgressZero() {
        let chunk = ChunkProgress(name: "chunk_01.bin", bytesDone: 0, total: 0)
        #expect(chunk.progress == 0)
    }

    @Test("分块名称即唯一标识")
    func chunkIdentifiable() {
        let chunk = ChunkProgress(name: "asset.pck", bytesDone: 10, total: 100)
        #expect(chunk.id == "asset.pck")
    }

    @Test("游戏状态显示中文")
    func statusTitle() {
        #expect(GameStatus.updateAvailable.title == "有可用更新")
        #expect(JobStatus.paused.title == "已暂停")
    }
}

