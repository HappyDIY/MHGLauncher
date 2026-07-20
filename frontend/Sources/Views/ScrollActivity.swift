import SwiftUI

// 标记当前是否正在滚动。用于在滚动过程中简化逐单元动画（跳过入场弹簧），
// 而静止、页面切换、初次加载时保持完整视觉。默认 false，使未包裹的视图
// 维持原有行为。
private struct ScrollActivityKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isScrolling: Bool {
        get { self[ScrollActivityKey.self] }
        set { self[ScrollActivityKey.self] = newValue }
    }
}

private struct ScrollActivityModifier: ViewModifier {
    @State private var scrolling = false

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                // 非 idle 即视为滚动中（拖拽、减速、系统动画滚动）。
                let active = phase != .idle
                if scrolling != active { scrolling = active }
            }
            .environment(\.isScrolling, scrolling)
    }
}

extension View {
    // 附加到滚动容器上：向其子树广播滚动状态，供逐单元入场动画据此在
    // 滚动过程中降级为即时呈现。
    func trackingScrollActivity() -> some View {
        modifier(ScrollActivityModifier())
    }
}
