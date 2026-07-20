import SwiftUI

// 入场动画修饰器：首次出现时以弹簧从位移/缩放/模糊/透明过渡到终态。
// 在滚动过程中新进入视区的单元直接呈现终态，跳过弹簧与逐帧模糊，以降低
// 滚动重灾页的每帧开销；静止、初次加载、页面切换时保持完整入场动画。
private struct MotionEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isScrolling) private var isScrolling
    @State private var appeared = false
    let role: MotionRole
    let order: Int

    func body(content: Content) -> some View {
        let spec = LauncherMotion.spec(
            for: role,
            reduceMotion: reduceMotion,
            order: order
        )
        // 修饰值始终施加以保证入场逐帧插值，逐像素一致；不再无条件包裹
        // compositingGroup（会为已 settle 的 cell 常驻离屏层，拖慢滚动）。
        content
            .opacity(appeared ? 1 : 0)
            .offset(appeared ? .zero : spec.offset)
            .scaleEffect(appeared ? 1 : spec.scale)
            .blur(radius: appeared ? 0 : spec.blur)
            .onAppear {
                guard !appeared else { return }
                if isScrolling {
                    appeared = true
                } else {
                    withAnimation(spec.animation) { appeared = true }
                }
            }
    }
}

extension View {
    func motionEntrance(
        _ role: MotionRole = .content,
        order: Int = 0
    ) -> some View {
        modifier(MotionEntranceModifier(role: role, order: order))
    }
}
