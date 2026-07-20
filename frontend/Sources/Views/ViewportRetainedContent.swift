import SwiftUI

struct ViewportRetentionState: Equatable {
    private(set) var isVisible = true
    private(set) var retainedHeight: CGFloat = 0

    var shouldRender: Bool {
        isVisible || retainedHeight == 0
    }

    // 结合导航页激活态：页面不可见时，仅在尚未测得占位高度前构建内容。
    func shouldRender(pageActive: Bool) -> Bool {
        guard pageActive else { return retainedHeight == 0 }
        return shouldRender
    }

    mutating func updateVisibility(_ isVisible: Bool) {
        self.isVisible = isVisible
    }

    mutating func updateHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        retainedHeight = height
    }

    mutating func invalidateMeasurement() {
        retainedHeight = 0
    }
}

struct ViewportRetainedContent<Content: View>: View {
    @Environment(\.navigationPageActive) private var pageActive
    @State private var retention = ViewportRetentionState()
    private let geometryID: AnyHashable?
    private let content: () -> Content

    init(
        geometryID: AnyHashable? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.geometryID = geometryID
        self.content = content
    }

    // 仅当页面处于激活态且在可视区内才构建高频内容；被缓存但不可见的页面
    // （opacity 0）以等高占位替代，从而停止其内部计时器与重绘。首次测量前
    // 仍构建以获得占位高度。
    private var rendersContent: Bool {
        retention.shouldRender(pageActive: pageActive)
    }

    var body: some View {
        Group {
            if rendersContent {
                content()
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: RetainedHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: retention.retainedHeight)
                    .accessibilityHidden(true)
            }
        }
        .onPreferenceChange(RetainedHeightKey.self) { height in
            retention.updateHeight(height)
        }
        .onChange(of: geometryID) {
            retention.invalidateMeasurement()
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
            retention.updateVisibility(isVisible)
        }
    }
}

private struct RetainedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
