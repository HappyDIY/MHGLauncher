import SwiftUI

struct HistoryWishBannerNavigation: View {
    let paging: HistoryWishBannerPaging
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("同期横幅", systemImage: "photo.stack")
                .font(.headline)
            Text("第 \(paging.page) / \(paging.count) 张")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .accessibilityLabel("第 \(paging.page) 张，共 \(paging.count) 张")
            Spacer(minLength: 12)
            Button("上一张", systemImage: "chevron.left", action: previous)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!paging.canGoPrevious)
                .motionHover()
            Button("下一张", systemImage: "chevron.right", action: next)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!paging.canGoNext)
                .motionHover()
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .padding(12)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.primary.opacity(0.08))
        }
        .accessibilityElement(children: .contain)
    }
}
