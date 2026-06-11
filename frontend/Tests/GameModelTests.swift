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
            message: ""
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
            message: ""
        )
        #expect(job.progress == 0)
    }

    @Test("游戏状态显示中文")
    func statusTitle() {
        #expect(GameStatus.updateAvailable.title == "有可用更新")
        #expect(JobStatus.paused.title == "已暂停")
    }
}

