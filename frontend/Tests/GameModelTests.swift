import Foundation
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
            lastUpdate: nil,
            revision: nil
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
            lastUpdate: nil,
            revision: nil
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
        #expect(JobStatus.pausing.title == "正在暂停")
        #expect(JobStatus.cancelling.title == "正在取消")
    }

    @Test("预下载任务类型解码")
    func predownloadKindDecodes() throws {
        let json = Data(#""predownload""#.utf8)
        let decoded = try JSONDecoder.api.decode(JobKind.self, from: json)
        #expect(decoded == .predownload)
    }

    @Test("磁盘空间检查结果解码")
    func spaceCheckDecodes() throws {
        let json = Data(#"{"available":1024,"required":2048,"sufficient":false}"#.utf8)
        let result = try JSONDecoder.api.decode(SpaceCheckResult.self, from: json)
        #expect(result.available == 1024)
        #expect(result.required == 2048)
        #expect(result.sufficient == false)
    }

    @Test("游戏状态包含预下载字段")
    func gameStateWithPredownload() throws {
        let json = Data(#"""
        {"install_path":"/games/gi","installed_version":"5.5.0","available_version":"5.6.0","status":"update_available","update_kind":"version_diff","download_bytes":1024,"predownload_version":"5.6.0","predownload_finished":false}
        """#.utf8)
        let state = try JSONDecoder.api.decode(GameState.self, from: json)
        #expect(state.predownloadVersion == "5.6.0")
        #expect(state.predownloadFinished == false)
        #expect(state.hasPendingPredownload)
        #expect(state.canStartPredownload)
    }

    @Test("预下载允许跨过常规更新直达预发布版本")
    func predownloadAllowsUpdateAvailableState() {
        let ready = gameState(status: .ready)
        #expect(ready.canStartPredownload)
        #expect(gameState(status: .updateAvailable, updateKind: "package_repair").canStartPredownload)
        #expect(!gameState(status: .notInstalled).canStartPredownload)
    }
}

private func gameState(status: GameStatus, updateKind: String = "full") -> GameState {
    GameState(
        installPath: "/games/gi",
        installedVersion: "6.6.0",
        availableVersion: "6.6.0",
        status: status,
        updateKind: updateKind,
        downloadBytes: 0,
        predownloadVersion: "6.7.0",
        predownloadFinished: false
    )
}
