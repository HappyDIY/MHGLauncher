import SwiftUI

struct PoolSelector: View {
    let details: [WishBannerDetail]
    @Binding var selection: String?

    private var sorted: [WishBannerDetail] {
        let order: [String] = ["301", "400", "302", "200", "100"]
        return details.sorted { a, b in
            let ai = order.firstIndex(of: a.gachaType) ?? 99
            let bi = order.firstIndex(of: b.gachaType) ?? 99
            return ai < bi
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(sorted) { detail in
                poolButton(detail)
            }
        }
    }

    private func poolButton(_ detail: WishBannerDetail) -> some View {
        let isSelected = selection == detail.id
        return Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected
                ? .regular.tint(detail.poolAccent.opacity(0.22)).interactive()
                : .clear.interactive(),
            in: .capsule
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}