import Testing
@testable import MHGLauncher

@Suite("动画系统")
struct MotionSystemTests {
    @Test("正常模式使用统一非线性曲线")
    func standardCurves() {
        #expect(
            LauncherMotion.spec(for: .micro, reduceMotion: false).curve
                == .snappy(duration: 0.18, bounce: 0.04)
        )
        #expect(
            LauncherMotion.spec(for: .navigation, reduceMotion: false).curve
                == .spring(duration: 0.52, bounce: 0.14)
        )
        #expect(
            LauncherMotion.spec(for: .emphasis, reduceMotion: false).curve
                == .spring(duration: 0.68, bounce: 0.26)
        )
    }

    @Test("交错延迟有统一上限")
    func cappedStagger() {
        let maximum = LauncherMotion.spec(
            for: .content,
            reduceMotion: false,
            order: LauncherMotion.maximumStaggerIndex
        )
        let overflow = LauncherMotion.spec(
            for: .content,
            reduceMotion: false,
            order: 100
        )
        #expect(maximum.delay == overflow.delay)
        #expect(maximum.delay == 0.28)
    }

    @Test("减少动态效果移除空间运动和循环")
    func reducedMotion() {
        for role in MotionRole.allCases {
            let spec = LauncherMotion.spec(
                for: role,
                reduceMotion: true,
                order: 8
            )
            #expect(spec.curve == .easeOut(duration: 0.12))
            #expect(spec.delay == 0)
            #expect(spec.offset == .zero)
            #expect(spec.scale == 1)
            #expect(spec.blur == 0)
            #expect(!spec.repeats)
        }
    }
}
