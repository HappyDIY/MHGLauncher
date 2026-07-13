import SwiftUI

enum AccessibilityLiveRegionPriority {
    case polite
    case assertive
}

extension View {
    func accessibilityLiveRegion(
        _ priority: AccessibilityLiveRegionPriority
    ) -> some View {
        let _ = priority
        return accessibilityAddTraits(.updatesFrequently)
    }
}
