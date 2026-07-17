import Testing
@testable import MHGLauncher

@Suite("祈愿操作进度")
struct WishOperationModelTests {
    @Test("未知总量使用不定进度")
    func indeterminateProgress() {
        var operation = WishOperationState(kind: .sync)
        operation.update(progress: 0.6, message: "同步中")
        operation.update(progress: nil, message: "正在读取分页")
        #expect(operation.progress == nil)
        #expect(operation.logs.count == 2)
    }

    @Test("后端任务日志只应用一次")
    func appliesBackendLogsOnce() {
        var operation = WishOperationState(kind: .sync)
        let task = WishTaskSnapshot(
            id: "task-1",
            kind: "sync",
            status: .running,
            progress: nil,
            logs: [
                WishTaskLogPayload(sequence: 1, message: "已读取第 1 页", emphasized: false)
            ],
            result: nil,
            error: "",
            errorCode: nil,
            revision: 1,
            targetUids: nil
        )
        operation.apply(task)
        operation.apply(task)
        #expect(operation.logs.count == 1)
        #expect(operation.logs.first?.message == "已读取第 1 页")
    }

    @Test("成功状态完成进度")
    func successState() {
        var operation = WishOperationState(kind: .exportUIGF)
        operation.succeed("导出完成")
        #expect(operation.status == .succeeded)
        #expect(operation.progress == 1)
        #expect(operation.logs.last?.emphasized == true)
    }

    @Test("失败状态保留当前进度")
    func failureState() {
        var operation = WishOperationState(kind: .importUIGF)
        operation.update(progress: 0.4, message: "校验中")
        operation.fail("格式错误")
        #expect(operation.status == .failed)
        #expect(operation.progress == 0.4)
    }

    @Test("操作进度更新不改变页面忙碌状态")
    @MainActor
    func stableActiveState() {
        let store = LauncherStore()
        store.wishOperation = WishOperationState(kind: .sync)
        #expect(store.isWishOperationActive)

        store.updateWishOperation(0.5, "同步中")
        #expect(store.isWishOperationActive)

        store.wishOperation = nil
        #expect(!store.isWishOperationActive)
    }
}
