import SwiftUI

enum MotionRole: CaseIterable, Sendable {
    case micro
    case selection
    case content
    case navigation
    case emphasis
    case progress
}

enum MotionCurve: Equatable, Sendable {
    case snappy(duration: Double, bounce: Double)
    case spring(duration: Double, bounce: Double)
    case smooth(duration: Double)
    case easeOut(duration: Double)
}

struct MotionSpec: Equatable, Sendable {
    let curve: MotionCurve
    let delay: Double
    let offset: CGSize
    let scale: CGFloat
    let blur: CGFloat
    let repeats: Bool

    var animation: Animation {
        let base = switch curve {
        case let .snappy(duration, bounce):
            Animation.snappy(duration: duration, extraBounce: bounce)
        case let .spring(duration, bounce):
            Animation.spring(duration: duration, bounce: bounce)
        case let .smooth(duration):
            Animation.smooth(duration: duration)
        case let .easeOut(duration):
            Animation.easeOut(duration: duration)
        }
        return base.delay(delay)
    }
}

enum LauncherMotion {
    static let staggerInterval = 0.035
    static let maximumStaggerIndex = 8
    static let progressTick = Animation.linear(duration: 0.08)
    static let shimmer = Animation.linear(duration: 1.8)
    static let activityGlow = Animation.easeInOut(duration: 1.4)
        .repeatForever()
    static let activityRotation = Animation.linear(duration: 1.3)
        .repeatForever(autoreverses: false)

    static func spec(
        for role: MotionRole,
        reduceMotion: Bool,
        order: Int = 0
    ) -> MotionSpec {
        if reduceMotion {
            return MotionSpec(
                curve: .easeOut(duration: 0.12),
                delay: 0,
                offset: .zero,
                scale: 1,
                blur: 0,
                repeats: false
            )
        }
        let curve: MotionCurve = switch role {
        case .micro: .snappy(duration: 0.18, bounce: 0.04)
        case .selection: .spring(duration: 0.32, bounce: 0.16)
        case .content: .spring(duration: 0.44, bounce: 0.18)
        case .navigation: .spring(duration: 0.52, bounce: 0.14)
        case .emphasis: .spring(duration: 0.68, bounce: 0.26)
        case .progress: .smooth(duration: 0.24)
        }
        let cappedOrder = min(max(order, 0), maximumStaggerIndex)
        return MotionSpec(
            curve: curve,
            delay: Double(cappedOrder) * staggerInterval,
            offset: CGSize(width: 0, height: role == .navigation ? 8 : 12),
            scale: role == .navigation ? 0.985 : 0.965,
            blur: role == .navigation ? 12 : 8,
            repeats: false
        )
    }

    static func animation(
        _ role: MotionRole,
        reduceMotion: Bool,
        order: Int = 0
    ) -> Animation {
        spec(for: role, reduceMotion: reduceMotion, order: order).animation
    }
}

private struct MotionTransitionValues: ViewModifier {
    let opacity: Double
    let offset: CGSize
    let scale: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        // 先合成为单层，再施加位移/缩放/模糊/透明，使动画每帧只栅格化一次子树，
        // 而非对玻璃、材质、图片、文本逐层重复合成。视觉结果保持一致。
        content
            .compositingGroup()
            .opacity(opacity)
            .offset(offset)
            .scaleEffect(scale)
            .blur(radius: blur)
    }
}

private struct MotionTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let role: MotionRole

    func body(content: Content) -> some View {
        let spec = LauncherMotion.spec(for: role, reduceMotion: reduceMotion)
        content.transition(
            .modifier(
                active: MotionTransitionValues(
                    opacity: 0,
                    offset: spec.offset,
                    scale: spec.scale,
                    blur: spec.blur
                ),
                identity: MotionTransitionValues(
                    opacity: 1,
                    offset: .zero,
                    scale: 1,
                    blur: 0
                )
            )
        )
    }
}

private struct MotionAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let role: MotionRole
    let value: Value

    func body(content: Content) -> some View {
        content.animation(
            LauncherMotion.animation(role, reduceMotion: reduceMotion),
            value: value
        )
    }
}

extension View {
    func motionTransition(_ role: MotionRole = .content) -> some View {
        modifier(MotionTransitionModifier(role: role))
    }

    func motionAnimation<Value: Equatable>(
        _ role: MotionRole,
        value: Value
    ) -> some View {
        modifier(MotionAnimationModifier(role: role, value: value))
    }
}
