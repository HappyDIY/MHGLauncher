import SwiftUI

struct ViewportRetentionState: Equatable {
    private(set) var isVisible = true
    private(set) var retainedHeight: CGFloat = 0

    var shouldRender: Bool {
        isVisible || retainedHeight == 0
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

    var body: some View {
        Group {
            if retention.shouldRender {
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
