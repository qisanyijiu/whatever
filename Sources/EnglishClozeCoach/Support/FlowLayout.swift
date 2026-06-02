import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(subviews: subviews, proposal: proposal).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(subviews: subviews, proposal: proposal)
        for item in arrangement.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                proposal: ProposedViewSize(item.frame.size)
            )
        }
    }

    private func arrange(subviews: Subviews, proposal: ProposedViewSize) -> Arrangement {
        let maxWidth = proposal.width ?? 720
        var items: [Arrangement.Item] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += lineHeight + lineSpacing
                lineHeight = 0
            }

            let frame = CGRect(origin: cursor, size: size)
            items.append(Arrangement.Item(index: index, frame: frame))
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, frame.maxX)
        }

        return Arrangement(
            size: CGSize(width: totalWidth, height: cursor.y + lineHeight),
            items: items
        )
    }

    private struct Arrangement {
        var size: CGSize
        var items: [Item]

        struct Item {
            var index: Int
            var frame: CGRect
        }
    }
}
