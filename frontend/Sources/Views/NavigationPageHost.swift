import SwiftUI

struct NavigationPageHost<Destination: Hashable, Content: View>: View {
    let destination: Destination
    let content: (Destination, Bool) -> Content
    @State private var cachedDestinations: [Destination]

    init(
        destination: Destination,
        @ViewBuilder content: @escaping (Destination, Bool) -> Content
    ) {
        self.destination = destination
        self.content = content
        _cachedDestinations = State(initialValue: [destination])
    }

    var body: some View {
        let pages = NavigationPageCache.including(
            destination,
            in: cachedDestinations
        )
        StableNavigationLayout {
            ForEach(pages, id: \.self) { page in
                let isCached = cachedDestinations.contains(page)
                content(page, page == destination)
                    .id(page)
                    .environment(\.navigationPageActive, page == destination)
                    .modifier(NavigationPageVisibilityModifier(
                        visible: page == destination,
                        initiallyVisible: isCached && page == destination
                    ))
                    .allowsHitTesting(page == destination)
                    .accessibilityHidden(page != destination)
                    .zIndex(page == destination ? 1 : 0)
            }
        }
        .onChange(of: destination) { _, value in
            guard !cachedDestinations.contains(value) else { return }
            cachedDestinations.append(value)
        }
    }
}

enum NavigationPageCache {
    static func including<Destination: Hashable>(
        _ destination: Destination,
        in cached: [Destination]
    ) -> [Destination] {
        cached.contains(destination) ? cached : cached + [destination]
    }
}

private struct NavigationPageVisibilityModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared: Bool
    let visible: Bool

    init(visible: Bool, initiallyVisible: Bool) {
        self.visible = visible
        _appeared = State(initialValue: initiallyVisible)
    }

    func body(content: Content) -> some View {
        let spec = LauncherMotion.spec(for: .navigation, reduceMotion: reduceMotion)
        let shown = visible && appeared
        content
            .compositingGroup()
            .opacity(shown ? 1 : 0)
            .offset(shown ? .zero : spec.offset)
            .scaleEffect(shown ? 1 : spec.scale)
            .blur(radius: shown ? 0 : spec.blur)
            .animation(spec.animation, value: visible)
            .onAppear {
                guard !appeared else { return }
                withAnimation(spec.animation) { appeared = true }
            }
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
