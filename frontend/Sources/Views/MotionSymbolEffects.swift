import SwiftUI

private struct MotionSymbolBounceModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.bounce, value: value)
        }
    }
}

extension View {
    func motionSymbolBounce<Value: Equatable>(value: Value) -> some View {
        modifier(MotionSymbolBounceModifier(value: value))
    }
}
