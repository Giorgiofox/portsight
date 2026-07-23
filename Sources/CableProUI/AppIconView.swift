import SwiftUI

/// The PortSight app icon, drawn in SwiftUI so it renders at any size.
/// Motif: a USB-C connector viewed through a "sight" — concentric lens rings
/// behind a clean Type-C plug, on an indigo→cyan squircle. Rendered to .icns
/// by scripts/make-icon.sh.
public struct AppIconView: View {
    public init() {}

    public var body: some View {
        // Design on a 1024 grid; scale to whatever frame we're rendered at.
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // Squircle background with depth.
                RoundedRectangle(cornerRadius: s * 0.2237, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.35, green: 0.30, blue: 0.98),
                                     Color(red: 0.10, green: 0.55, blue: 0.95),
                                     Color(red: 0.05, green: 0.70, blue: 0.90)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: s * 0.2237, style: .continuous)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .top, endPoint: .center)))

                // "Sight" lens rings.
                ForEach(0..<2) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.22 - Double(i) * 0.08), lineWidth: s * 0.012)
                        .frame(width: s * (0.62 + Double(i) * 0.16))
                }

                // USB-C connector: outer white capsule + inner slot.
                ZStack {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: s * 0.46, height: s * 0.235)
                        .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.01)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.10, green: 0.30, blue: 0.60),
                                     Color(red: 0.06, green: 0.18, blue: 0.42)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(width: s * 0.30, height: s * 0.095)
                }

                // Power spark accent.
                Image(systemName: "bolt.fill")
                    .font(.system(size: s * 0.12, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: Color(red: 0.1, green: 0.5, blue: 0.95).opacity(0.6),
                            radius: s * 0.02)
                    .offset(x: s * 0.24, y: s * 0.24)
            }
            .frame(width: s, height: s)
        }
    }
}
