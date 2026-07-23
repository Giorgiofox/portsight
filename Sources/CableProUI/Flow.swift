import SwiftUI
import WhatCableCore

/// Minimal wrapping flow layout (macOS 13+ Layout protocol).
struct FlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// PDO chips for the PD Contract Inspector; the winning profile is filled green.
struct FlowChips: View {
    let options: [PowerOption]
    let winning: PowerOption?

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isWin = opt == winning
                Text(label(opt))
                    .font(.system(size: 10, design: .rounded).weight(isWin ? .bold : .medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(isWin ? Color.green.opacity(0.85)
                                                     : Color.white.opacity(0.06)))
                    .foregroundStyle(isWin ? Color.white : .secondary)
            }
        }
    }

    private func label(_ o: PowerOption) -> String {
        let v = Double(o.voltageMV) / 1000, a = Double(o.maxCurrentMA) / 1000
        return String(format: "%gV·%gA", v, a)
    }
}
