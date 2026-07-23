import SwiftUI
import WhatCableCore

// Visual system for CablePro. Dark-first, but uses semantic colors so it
// adapts to light mode too.

public enum Theme {
    static let cardCorner: CGFloat = 16
    static let cardStroke = Color.white.opacity(0.08)

    /// Offscreen rendering (ImageRenderer) can't draw `Material` — it comes out
    /// transparent. The preview harness sets this to swap materials for solid
    /// fills and use an explicit dark backdrop. The live app leaves it false.
    public static var flat = false

    // Layered backdrop for the popover.
    @ViewBuilder static var backdrop: some View {
        Group {
            if flat {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.09, blue: 0.12),
                             Color(red: 0.03, green: 0.03, blue: 0.05)],
                    startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(
                    colors: [Color(nsColor: .windowBackgroundColor),
                             Color(nsColor: .windowBackgroundColor).opacity(0.92)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
        .overlay(
            RadialGradient(
                colors: [Color.accentColor.opacity(0.14), .clear],
                center: .topLeading, startRadius: 0, endRadius: 320)
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// Card surface: translucent material live, solid fill in flat/preview mode.
    func cardSurface(stroke: Color = Theme.cardStroke, dim: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(Theme.flat ? AnyShapeStyle(Color.white.opacity(0.06))
                                 : AnyShapeStyle(.regularMaterial))
                .opacity(dim ? 0.6 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .stroke(stroke, lineWidth: 1))
        )
    }
}

// MARK: - Port status → color + icon

extension PortSummary.Status {
    var accent: Color {
        switch self {
        case .empty:            return .secondary
        case .charging:         return .green
        case .batteryFull:      return .teal
        case .dataDevice:       return .blue
        case .thunderboltCable: return .purple
        case .displayCable:     return .orange
        case .unknown:          return .gray
        }
    }

    var symbol: String {
        switch self {
        case .empty:            return "cable.connector"
        case .charging:         return "bolt.fill"
        case .batteryFull:      return "battery.100.bolt"
        case .dataDevice:       return "externaldrive.connected.to.line.below"
        case .thunderboltCable: return "bolt.horizontal.fill"
        case .displayCable:     return "display"
        case .unknown:          return "questionmark.circle"
        }
    }
}

// MARK: - Speed tier → color

extension LinkSpeed.Tier {
    var color: Color {
        switch self {
        case .usb2:   return .gray
        case .usb5g:  return .blue
        case .usb10g: return .teal
        case .usb20g: return .green
        case .tb40:   return .purple
        case .tb80:   return .pink
        }
    }
}

// MARK: - Reusable chip

struct Chip: View {
    let text: String
    var color: Color = .accentColor
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(filled ? 0.9 : 0.15))
            )
            .foregroundStyle(filled ? Color.white : color)
    }
}
