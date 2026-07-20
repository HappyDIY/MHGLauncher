import SwiftUI

enum MotionHoverRole: CaseIterable, Sendable {
    case subtle
    case control
    case prominent
    case selection
    case destructive
}

struct MotionHoverSpec: Equatable, Sendable {
    let scale: CGFloat
    let lift: CGFloat
    let rotation: Double
    let brightness: Double
    let saturation: Double
    let shadowRadius: CGFloat
}

enum LauncherInteractionMotion {
    static func hoverSpec(
        for role: MotionHoverRole,
        reduceMotion: Bool
    ) -> MotionHoverSpec {
        if reduceMotion {
            return MotionHoverSpec(
                scale: 1,
                lift: 0,
                rotation: 0,
                brightness: 0.025,
                saturation: 1.04,
                shadowRadius: 0
            )
        }
        return switch role {
        case .subtle:
            MotionHoverSpec(
                scale: 1,
                lift: 0,
                rotation: 0,
                brightness: 0.03,
                saturation: 1.04,
                shadowRadius: 2
            )
        case .control:
            MotionHoverSpec(
                scale: 1.025,
                lift: -1,
                rotation: 0.6,
                brightness: 0.04,
                saturation: 1.06,
                shadowRadius: 6
            )
        case .prominent:
            MotionHoverSpec(
                scale: 1.04,
                lift: -2,
                rotation: 1.2,
                brightness: 0.06,
                saturation: 1.1,
                shadowRadius: 12
            )
        case .selection:
            MotionHoverSpec(
                scale: 1.055,
                lift: -1,
                rotation: 1.8,
                brightness: 0.05,
                saturation: 1.12,
                shadowRadius: 10
            )
        case .destructive:
            MotionHoverSpec(
                scale: 1.02,
                lift: -1,
                rotation: -0.6,
                brightness: 0.035,
                saturation: 1.08,
                shadowRadius: 8
            )
        }
    }
}

private struct MotionHoverModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    let role: MotionHoverRole

    func body(content: Content) -> some View {
        let active = isHovering && isEnabled
        let spec = LauncherInteractionMotion.hoverSpec(
            for: role,
            reduceMotion: reduceMotion
        )
        content
            .compositingGroup()
            .scaleEffect(active ? spec.scale : 1)
            .offset(y: active ? spec.lift : 0)
            .rotation3DEffect(
                .degrees(active ? spec.rotation : 0),
                axis: (x: 1, y: -1, z: 0),
                perspective: 0.65
            )
            .brightness(active ? spec.brightness : 0)
            .saturation(active ? spec.saturation : 1)
            .shadow(
                color: shadowColor.opacity(active ? 0.28 : 0),
                radius: active ? spec.shadowRadius : 0,
                y: active ? max(-spec.lift, 1) : 0
            )
            .animation(
                LauncherMotion.animation(
                    .micro,
                    reduceMotion: reduceMotion
                ),
                value: active
            )
            .onHover { isHovering = $0 }
            .onChange(of: isEnabled) {
                if !isEnabled { isHovering = false }
            }
    }

    private var shadowColor: Color {
        role == .destructive ? .red : .accentColor
    }
}

private struct MotionScrollAppearanceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // 先合成为单层再做滚动过渡，模糊/缩放/透明每帧只栅格化一次子树。
            content
                .compositingGroup()
                .scrollTransition(
                    .animated(LauncherMotion.animation(
                        .content,
                        reduceMotion: false
                    ))
                ) { view, phase in
                    view
                        .opacity(phase.isIdentity ? 1 : 0.68)
                        .scaleEffect(phase.isIdentity ? 1 : 0.94)
                        .blur(radius: phase.isIdentity ? 0 : 4)
                }
        }
    }
}

extension View {
    func motionHover(_ role: MotionHoverRole = .control) -> some View {
        modifier(MotionHoverModifier(role: role))
    }

    func motionScrollAppearance() -> some View {
        modifier(MotionScrollAppearanceModifier())
    }
}
