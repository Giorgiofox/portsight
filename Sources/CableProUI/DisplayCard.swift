import SwiftUI

// External display diagnostics card (feature #3 / #9).
struct DisplayCard: View {
    let display: DisplayVM

    private var accent: Color { display.isWarning ? .orange : .orange.opacity(0.9) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "display")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.orange.opacity(0.16)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(display.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Spacer(minLength: 0)
                    if let mode = display.modeLabel {
                        Chip(text: mode, color: .orange, filled: true)
                    }
                }
                // Link facts: lanes + rate + delivered Gbps.
                HStack(spacing: 6) {
                    factChip("\(display.lanes)/\(display.maxLanes) lanes")
                    if let rate = display.rateDescription { factChip(rate) }
                    if let g = display.deliveredGbps { factChip(String(format: "%.0f Gbps", g)) }
                }
                if !display.summary.isEmpty {
                    Text(display.summary)
                        .font(.caption)
                        .foregroundStyle(display.isWarning ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .cardSurface(stroke: Color.orange.opacity(0.22))
    }

    private func factChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .rounded).weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}
