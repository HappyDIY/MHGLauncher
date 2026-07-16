import SwiftUI

struct WishOperationHost: View {
    @Bindable var store: LauncherStore

    @ViewBuilder
    var body: some View {
        if let operation = store.wishOperation {
            WishOperationOverlay(operation: operation) {
                store.wishOperation = nil
            }
        }
    }
}
