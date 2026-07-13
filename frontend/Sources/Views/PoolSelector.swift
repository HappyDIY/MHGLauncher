import SwiftUI

struct PoolSelector: View {
    let details: [WishBannerDetail]
    @Binding var selection: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    private var sorted: [WishBannerDetail] {
        let order: [String] = ["301", "400", "302", "200", "100"]
        return details.sorted { a, b in
            let ai = order.firstIndex(of: a.gachaType) ?? 99
            let bi = order.firstIndex(of: b.gachaType) ?? 99
            return ai < bi
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(sorted) { detail in
                    poolButton(detail)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func poolButton(_ detail: WishBannerDetail) -> some View {
        let isSelected = selection == detail.id
        return Button {
            withAnimation(LauncherMotion.animation(
                .selection,
                reduceMotion: reduceMotion
            )) {
                selection = detail.id
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: detail.poolIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isSelected ? AnyShapeStyle(detail.poolGradient) : AnyShapeStyle(.quaternary))
                    )
                if isSelected {
                    Text(detail.poolLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, isSelected ? 14 : 8)
            .padding(.vertical, 8)
            .background {
                if isSelected && !reduceMotion {
                    Capsule()
                        .fill(detail.poolAccent.opacity(0.1))
                        .matchedGeometryEffect(
                            id: "pool-selection",
                            in: selectionNamespace
                        )
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .motionHover(.selection)
        .glassEffect(
            isSelected
                ? .regular.tint(detail.poolAccent.opacity(0.22)).interactive()
                : .clear.interactive(),
            in: .capsule
        )
        .accessibilityLabel(detail.poolLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .motionAnimation(.selection, value: isSelected)
    }
}
