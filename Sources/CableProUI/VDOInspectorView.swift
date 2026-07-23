import SwiftUI
import WhatCableCore

// Raw VDO Identity inspector (pro feature #10): shows the decoded USB-PD
// Discover Identity VDOs from a cable e-marker or connected device.

// Mockable view-model, following the BatteryVM/DisplayVM/SpeedVM pattern.
struct VDOInfo: Equatable {
    let kind: String            // "Cable e-marker (SOP')" / "Device (SOP)" …
    let vendorName: String
    let vidHex: String          // "0x05AC"
    let pidHex: String
    let bcdHex: String
    let pdRevision: String?     // "PD 3.0"
    let certXIDHex: String?     // "0x0000ABCD" when certified
    let speedLabel: String?     // cable VDO speed
    let currentLabel: String?
    let typeLabel: String?
    let maxWatts: Int?
    let eprCapable: Bool
    let vdosHex: [String]       // ["0x18000000", …]

    init(_ sop: USBPDSOP) {
        switch sop.endpoint {
        case .sop:            kind = "Device (SOP)"
        case .sopPrime:       kind = "Cable e-marker (SOP′)"
        case .sopDoublePrime: kind = "Cable far-end (SOP″)"
        case .unknown:        kind = "Identity"
        }
        vendorName = CableDB.vendorName(vid: sop.vendorID) ?? "Unknown vendor"
        vidHex = String(format: "0x%04X", sop.vendorID)
        pidHex = String(format: "0x%04X", sop.productID)
        bcdHex = String(format: "0x%04X", sop.bcdDevice)
        pdRevision = sop.pdRevisionLabel

        if let cert = sop.certStatVDO, cert.isPresent {
            certXIDHex = String(format: "0x%08X", cert.xid)
        } else {
            certXIDHex = nil
        }

        if let cable = sop.cableVDO {
            speedLabel = cable.reportSpeedLabel
            currentLabel = cable.current.label
            switch cable.cableType {
            case .passive: typeLabel = "passive"
            case .active:  typeLabel = "active"
            case .other:   typeLabel = "other"
            }
            maxWatts = cable.maxWatts
            eprCapable = cable.eprCapable
        } else {
            speedLabel = nil; currentLabel = nil; typeLabel = nil
            maxWatts = nil; eprCapable = false
        }

        vdosHex = sop.vdos.map { String(format: "0x%08X", $0) }
    }

    // Memberwise init for previews.
    init(kind: String, vendorName: String, vidHex: String, pidHex: String, bcdHex: String,
         pdRevision: String?, certXIDHex: String?, speedLabel: String?, currentLabel: String?,
         typeLabel: String?, maxWatts: Int?, eprCapable: Bool, vdosHex: [String]) {
        self.kind = kind; self.vendorName = vendorName
        self.vidHex = vidHex; self.pidHex = pidHex; self.bcdHex = bcdHex
        self.pdRevision = pdRevision; self.certXIDHex = certXIDHex
        self.speedLabel = speedLabel; self.currentLabel = currentLabel
        self.typeLabel = typeLabel; self.maxWatts = maxWatts
        self.eprCapable = eprCapable; self.vdosHex = vdosHex
    }
}

struct VDOInspectorView: View {
    let info: VDOInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: kind + vendor + IDs.
            HStack(spacing: 8) {
                Image(systemName: "number.square.fill").foregroundStyle(.indigo)
                Text(info.kind)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer(minLength: 0)
                if let pd = info.pdRevision { Chip(text: pd, color: .indigo) }
            }
            Text(info.vendorName)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.primary)

            // Identity + decoded highlights as chips.
            FlowChips2 {
                idChip("VID", info.vidHex)
                idChip("PID", info.pidHex)
                idChip("bcd", info.bcdHex)
                if let x = info.certXIDHex { idChip("XID", x, color: .green) }
                if let s = info.speedLabel { hlChip(s) }
                if let c = info.currentLabel { hlChip(c) }
                if let t = info.typeLabel { hlChip(t) }
                if let w = info.maxWatts { hlChip("\(w) W") }
                if info.eprCapable { Chip(text: "EPR", color: .purple, filled: true) }
            }

            // Raw VDOs.
            if !info.vdosHex.isEmpty {
                Text("RAW VDOs").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(info.vdosHex.enumerated()), id: \.offset) { i, hex in
                        HStack(spacing: 8) {
                            Text("VDO\(i)")
                                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 34, alignment: .leading)
                            Text(hex)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(12)
        .cardSurface(stroke: Color.indigo.opacity(0.22))
    }

    private func idChip(_ label: String, _ value: String, color: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 10, design: .monospaced).weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func hlChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .rounded).weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.indigo.opacity(0.18)))
            .foregroundStyle(Color.indigo)
    }
}

// Tiny wrapping row for the chips (self-contained so this file has no external deps).
private struct FlowChips2: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rh: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rh + 5; rh = 0 }
            x += sz.width + 5; rh = max(rh, sz.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rh)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rh: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rh + 5; rh = 0 }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += sz.width + 5; rh = max(rh, sz.height)
        }
    }
}
