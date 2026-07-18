import SwiftUI

struct NavigationPageHost<Destination: Hashable, Content: View>: View {
    let destination: Destination
    @ViewBuilder let content: Content

    var body: some View {
        StableNavigationLayout {
            content
                .id(destination)
                .motionTransition(.navigation)
        }
        .motionAnimation(.navigation, value: destination)
    }
}

struct StableNavigationLayout: Layout {
    struct Cache {
        var fallbackSize = CGSize.zero
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        if let width = proposal.width, let height = proposal.height {
            return CGSize(width: width, height: height)
        }
        let fallback = subviews.first?.sizeThatFits(proposal) ?? cache.fallbackSize
        cache.fallbackSize = fallback
        return Self.resolvedSize(proposal: proposal, fallback: fallback)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let childProposal = ProposedViewSize(width: bounds.width, height: bounds.height)
        for subview in subviews {
            subview.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: childProposal
            )
        }
    }

    static func resolvedSize(
        proposal: ProposedViewSize,
        fallback: CGSize
    ) -> CGSize {
        CGSize(
            width: proposal.width ?? fallback.width,
            height: proposal.height ?? fallback.height
        )
    }
}
