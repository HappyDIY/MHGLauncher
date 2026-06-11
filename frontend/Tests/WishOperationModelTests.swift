import Testing
@testable import MHGLauncher

@Suite("祈愿操作进度")
struct WishOperationModelTests {
    @Test("进度只能向前推进")
    func monotonicProgress() {
        var operation = WishOperationState(kind: .sync)
        operation.update(progress: 0.6, message: "同步中")
        operation.update(progress: 0.2, message: "稍候")
        #expect(operation.progress == 0.6)
        #expect(operation.logs.count == 2)
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
}
