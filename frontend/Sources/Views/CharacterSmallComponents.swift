import SwiftUI

struct SectionPanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            Divider()
            content
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlowTags: View {
    let values: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.14), in: .capsule)
            }
        }
    }
}

struct CharacterPropertyLine: View {
    let property: CharacterProperty?
    let bold: Bool

    var body: some View {
        HStack {
            Text(property?.name ?? "")
                .foregroundStyle(bold ? .primary : .secondary)
            Spacer()
            Text(property?.value ?? "")
                .fontWeight(bold ? .bold : .regular)
            if let add = property?.addValue, !add.isEmpty {
                Text(add)
                    .foregroundStyle(.green)
            }
        }
        .font(.caption)
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for row in rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: .unspecified
                )
            }
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? 320
        var rows: [FlowRow] = [FlowRow(y: 0, width: 0, height: 0, items: [])]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows.removeLast()
            let x = row.items.isEmpty ? 0 : row.width + spacing
            if x + size.width > maxWidth, !row.items.isEmpty {
                rows.append(row)
                row = FlowRow(y: (rows.last?.y ?? 0) + (rows.last?.height ?? 0) + spacing, width: 0, height: 0, items: [])
            }
            let itemX = row.items.isEmpty ? 0 : row.width + spacing
            row.items.append(FlowItem(index: index, x: itemX))
            row.width = itemX + size.width
            row.height = max(row.height, size.height)
            rows.append(row)
        }
        return rows
    }
}

private struct FlowRow {
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var items: [FlowItem]
}

private struct FlowItem {
    var index: Int
    var x: CGFloat
}
