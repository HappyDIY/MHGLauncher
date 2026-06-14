import SwiftUI

struct PoolSelector: View {
    let details: [WishBannerDetail]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(details) { detail in
                        poolButton(detail)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func poolButton(_ detail: WishBannerDetail) -> some View {
        let isSelected = selection == detail.id
        return Button {
            selection = detail.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: detail.poolIcon)
                    .foregroundStyle(isSelected ? detail.poolAccent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.poolName)
                        .font(.subheadline.weight(.semibold))
                    Text("\(detail.lastPity) 垫 · \(detail.total) 抽")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected
                ? .regular.tint(detail.poolAccent.opacity(0.16)).interactive()
                : .clear.interactive(),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
