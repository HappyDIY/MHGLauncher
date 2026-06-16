import SwiftUI

struct WishLoadingPlaceholder: View {
    @State private var offset: CGFloat = -420

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("祈愿概览", systemImage: "chart.bar.xaxis").font(.headline)
                    Text("正在载入...").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                shimmer(62, 28, 6)
                shimmer(62, 28, 6)
                shimmer(62, 28, 6)
                shimmer(62, 28, 6)
            }
            .padding(.horizontal, 20).padding(.vertical, 15)
            .glassEffect(.regular.tint(.cyan.opacity(0.05)), in: .rect(cornerRadius: 22))
            HStack(spacing: 14) {
                shimmer(360, nil, 22)
                shimmer(nil, nil, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await run() }
    }

    private func shimmer(_ w: CGFloat?, _ h: CGFloat?, _ r: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: r)
            .fill(.quaternary)
            .frame(width: w, height: h)
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.12), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: (w ?? 200) * 2, height: h ?? 200)
                .offset(x: offset)
            }
            .mask(RoundedRectangle(cornerRadius: r).frame(width: w, height: h))
    }

    private func run() async {
        while !Task.isCancelled {
            withAnimation(.linear(duration: 1.8)) { offset = 600 }
            try? await Task.sleep(for: .seconds(2.0))
            offset = -420
        }
    }
}