import SwiftUI
import WhatCableCore

// USB-C 24-pin connector diagram (pro feature "pin diagram"). Shows the two
// physical rows (A1–A12 / B12–B1), colour-coded by function, with dynamic
// high-speed pins highlighted when a protocol is actually routed through them.

struct PinDiagramVM: Equatable {
    enum Kind: Equatable {
        case ground, vbus, cc, usb2, usb3, dp, sbu, inactive

        var color: Color {
            switch self {
            case .ground:   return .gray
            case .vbus:     return .green
            case .cc:       return .purple
            case .usb2:     return .blue
            case .usb3:     return .cyan
            case .dp:       return .orange
            case .sbu:      return .pink
            case .inactive: return .secondary
            }
        }
        var legend: String {
            switch self {
            case .ground: return "GND"
            case .vbus: return "VBUS"
            case .cc: return "CC"
            case .usb2: return "USB 2.0"
            case .usb3: return "USB 3 / TB"
            case .dp: return "DisplayPort"
            case .sbu: return "SBU / AUX"
            case .inactive: return "unused"
            }
        }
    }

    struct Pin: Identifiable, Equatable {
        let id: String        // "A1" … "B1"
        let label: String     // signal short label
        let kind: Kind
        let active: Bool       // carrying a live dynamic signal
    }

    let topRow: [Pin]
    let bottomRow: [Pin]
    let orientationLabel: String
    let summary: String

    /// True when any high-speed pin is carrying data.
    var hasActivity: Bool { (topRow + bottomRow).contains { $0.active } }

    /// Which functional groups appear (for the legend).
    var legendKinds: [Kind] {
        var seen: [Kind] = []
        for p in topRow + bottomRow where !seen.contains(p.kind) { seen.append(p.kind) }
        return seen.filter { $0 != .inactive }
    }

    // MARK: inits

    // Memberwise (previews).
    init(topRow: [Pin], bottomRow: [Pin], orientationLabel: String, summary: String) {
        self.topRow = topRow; self.bottomRow = bottomRow
        self.orientationLabel = orientationLabel; self.summary = summary
    }

    /// Best path: real pin routing from IOKit's decoded USBCPinMap.
    init(_ map: USBCPinMap) {
        self.topRow = map.topRow.map { Self.pin(from: $0) }
        self.bottomRow = map.bottomRow.map { Self.pin(from: $0) }
        self.orientationLabel = map.orientationLabel
        self.summary = map.signalSummary
    }

    /// Fallback: no pin-config dict, so lay out the fixed Type-C pinout and
    /// highlight the high-speed pins by which transports are active.
    init(orientation: Int?, activeTransports: [String]) {
        let hasHS = activeTransports.contains("USB3") || activeTransports.contains("CIO")
        let hasDP = activeTransports.contains("DisplayPort")
        // High-speed data pins take DP colour when DP alt-mode is up, else USB3/TB.
        let dKind: Kind = (hasHS || hasDP) ? (hasDP ? .dp : .usb3) : .inactive
        let dActive = hasHS || hasDP

        func fixed(_ id: String, _ k: Kind) -> Pin {
            Pin(id: id, label: k.legend, kind: k, active: false)
        }
        func data(_ id: String, _ label: String) -> Pin {
            Pin(id: id, label: label, kind: dKind, active: dActive)
        }
        func sbu(_ id: String) -> Pin {
            Pin(id: id, label: "SBU", kind: hasDP ? .sbu : .inactive, active: hasDP)
        }
        self.topRow = [
            fixed("A1", .ground), data("A2", "TX1+"), data("A3", "TX1-"),
            fixed("A4", .vbus), fixed("A5", .cc), fixed("A6", .usb2), fixed("A7", .usb2),
            sbu("A8"), fixed("A9", .vbus), data("A10", "RX2-"), data("A11", "RX2+"),
            fixed("A12", .ground),
        ]
        self.bottomRow = [
            fixed("B12", .ground), data("B11", "RX1+"), data("B10", "RX1-"),
            fixed("B9", .vbus), sbu("B8"), fixed("B7", .usb2), fixed("B6", .usb2),
            fixed("B5", .cc), fixed("B4", .vbus), data("B3", "TX2-"), data("B2", "TX2+"),
            fixed("B1", .ground),
        ]
        self.orientationLabel = orientation == 1 ? "Normal" : (orientation == 2 ? "Flipped" : "Unknown")
        switch (hasHS, hasDP) {
        case (true, true): summary = "USB 3 / TB + DisplayPort"
        case (true, false): summary = "USB 3 / Thunderbolt"
        case (false, true): summary = "DisplayPort Alt Mode"
        case (false, false): summary = "Power / USB 2.0 only"
        }
    }

    private static func pin(from p: USBCPinMap.Pin) -> Pin {
        let (kind, active): (Kind, Bool)
        switch p.signal {
        case .ground:              (kind, active) = (.ground, false)
        case .vbus:                (kind, active) = (.vbus, false)
        case .cc:                  (kind, active) = (.cc, false)
        case .usb2:                (kind, active) = (.usb2, false)
        case .usb3PairA, .usb3PairB: (kind, active) = (.usb3, true)
        case .dpLane:              (kind, active) = (.dp, true)
        case .dpAux:               (kind, active) = (.sbu, true)
        case .inactive:            (kind, active) = (.inactive, false)
        case .unknown:             (kind, active) = (.inactive, false)
        }
        return Pin(id: p.id, label: p.signal.label, kind: kind, active: active)
    }
}

private extension PinDiagramVM.Kind {
    var isDynamic: Bool {
        switch self { case .usb3, .dp, .sbu: return true; default: return false }
    }
}

struct PinDiagramView: View {
    let diagram: PinDiagramVM

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Connector pinout", systemImage: "cablecar")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Chip(text: diagram.orientationLabel, color: .secondary)
                Chip(text: diagram.summary, color: diagram.hasActivity ? .cyan : .secondary,
                     filled: diagram.hasActivity)
            }
            pinRow(diagram.topRow)
            pinRow(diagram.bottomRow)
            legend
        }
        .padding(12)
        .cardSurface()
    }

    private func pinRow(_ pins: [PinDiagramVM.Pin]) -> some View {
        HStack(spacing: 3) {
            ForEach(pins) { pin in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(pin.kind.color.opacity(pin.kind == .inactive ? 0.18
                                                     : (pin.active ? 0.95 : 0.5)))
                        .frame(height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(pin.active ? Color.white.opacity(0.5) : .clear, lineWidth: 1))
                    Text(pin.id)
                        .font(.system(size: 6.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(Array(diagram.legendKinds.enumerated()), id: \.offset) { _, k in
                HStack(spacing: 3) {
                    Circle().fill(k.color).frame(width: 6, height: 6)
                    Text(k.legend).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
