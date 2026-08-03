import SwiftUI
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

    @Test("悬停角色提供不同强度的交互反馈")
    func hoverRoles() {
        let subtle = LauncherInteractionMotion.hoverSpec(
            for: .subtle,
            reduceMotion: false
        )
        let prominent = LauncherInteractionMotion.hoverSpec(
            for: .prominent,
            reduceMotion: false
        )
        let selection = LauncherInteractionMotion.hoverSpec(
            for: .selection,
            reduceMotion: false
        )
        #expect(subtle.scale == 1)
        #expect(prominent.scale > subtle.scale)
        #expect(prominent.lift < subtle.lift)
        #expect(selection.rotation > prominent.rotation)
    }

    @Test("减少动态效果仅保留悬停颜色反馈")
    func reducedHover() {
        for role in MotionHoverRole.allCases {
            let spec = LauncherInteractionMotion.hoverSpec(
                for: role,
                reduceMotion: true
            )
            #expect(spec.scale == 1)
            #expect(spec.lift == 0)
            #expect(spec.rotation == 0)
            #expect(spec.shadowRadius == 0)
            #expect(spec.brightness > 0)
        }
    }

    @MainActor
    @Test("过渡只在动画帧启用离屏合成")
    func transitionCompositionLifetime() {
        let identity = MotionTransitionValues(
            opacity: 1,
            offset: .zero,
            scale: 1,
            blur: 0
        )
        var active = MotionTransitionValues(
            opacity: 0,
            offset: CGSize(width: 0, height: 12),
            scale: 0.96,
            blur: 8
        )
        let values = active.animatableData
        active.animatableData = values

        #expect(active.opacity == 0)
        #expect(active.offset.height == 12)
        #expect(renderTransition(identity) != nil)
        #expect(renderTransition(active) != nil)
    }

    @MainActor
    @Test("游戏启动仪式覆盖完整等待阶段")
    func gameLaunchCeremony() {
        let store = LauncherStore()
        store.isLaunchingGame = true
        #expect(renderCeremony(store) != nil)

        store.isLaunchingGame = false
        for status in [
            GameLaunchStatus.preparing,
            .starting,
            .waitingWindow
        ] {
            store.gameLaunch = gameLaunch(status)
            #expect(renderCeremony(store) != nil)
        }

        store.gameLaunch = gameLaunch(.running)
        #expect(renderCeremony(store) != nil)
        store.gameLaunch = nil
        #expect(renderCeremony(store) != nil)
    }

    @MainActor
    private func renderCeremony(_ store: LauncherStore) -> NSImage? {
        ImageRenderer(
            content: GameLaunchCeremonyHost(store: store)
                .frame(width: 800, height: 600)
        ).nsImage
    }

    private func gameLaunch(_ status: GameLaunchStatus) -> GameLaunch {
        GameLaunch(
            id: "launch-1", status: status, message: "", performanceProfile: .optimized,
            metalHud: false, networkDebug: false, wineLog: false,
            progress: status == .stopped ? 1 : 0.5, logs: [],
            startedAt: "2026-07-06T00:00:00Z", updatedAt: "2026-07-06T00:00:01Z", revision: 1
        )
    }

    @MainActor
    private func renderTransition(_ values: MotionTransitionValues) -> NSImage? {
        ImageRenderer(
            content: Text("动画")
                .modifier(values)
                .frame(width: 160, height: 80)
        ).nsImage
    }
}
