import SwiftUI
import WhatCableCore

struct PortCard: View {
    let vm: PortVM
    var livePower: PortLivePower? = nil
    // Collapsed by default live; expanded in preview (flat) so the render shows it.
    @State private var expanded = Theme.flat

    private var s: PortSummary { vm.summary }
    private var accent: Color { s.status.accent }
    private var isEmpty: Bool { s.status == .empty }
    private var hasDetails: Bool { vm.pins != nil || vm.vdo != nil || !vm.events.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(vm.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    if let type = vm.type {
                        Chip(text: type, color: .secondary)
                    }
                    Spacer(minLength: 0)
                    if let speed = s.linkSpeed {
                        Chip(text: speed.badge, color: speed.tier.color, filled: true)
                    }
                }
                Text(s.headline)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(isEmpty ? .secondary : .primary)
                if !s.subtitle.isEmpty {
                    Text(s.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Liquid detection — surfaced prominently as a warning.
                if let liquid = vm.liquid, liquid.liquidDetected {
                    liquidBadge(liquid).padding(.top, 4)
                }
                // Cable speed panel — the headline feature, right up top.
                if let speed = vm.speed, speed.hasChain {
                    speedPanel(speed).padding(.top, 6)
                }
                if !s.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(s.bullets.prefix(4).enumerated()), id: \.offset) { _, b in
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(accent.opacity(0.7))
                                    .frame(width: 4, height: 4).padding(.top, 6)
                                Text(b).font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                if !vm.pdOptions.isEmpty {
                    pdContract.padding(.top, 4)
                }
                if let cc = vm.ccAdvertMA {
                    ccRow(cc).padding(.top, 2)
                }
                if let lp = livePower {
                    livePowerLine(lp).padding(.top, 3)
                }
                if vm.health.hasAny {
                    healthRow.padding(.top, 2)
                }
                if hasDetails {
                    detailsSection.padding(.top, 3)
                }
            }
        }
        .padding(12)
        .cardSurface(stroke: accent.opacity(isEmpty ? 0.06 : 0.22), dim: isEmpty)
    }

    // MARK: - Per-port live power (feature #4)

    private func livePowerLine(_ lp: PortLivePower) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.circle.fill").foregroundStyle(.green)
            Text(String(format: "%.1f W", lp.watts)).fontWeight(.bold)
            Text(String(format: "· %.2f V · %.2f A", lp.volts, lp.amps)).foregroundStyle(.secondary)
        }
        .font(.system(.caption, design: .rounded)).monospacedDigit()
    }

    // MARK: - Expandable nerdy details (pins #pin, VDO #10, event trace #8)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    Text("Details").fontWeight(.semibold)
                    Spacer()
                    if !expanded {
                        Text([vm.pins != nil ? "pins" : nil,
                              vm.vdo != nil ? "VDO" : nil,
                              vm.events.isEmpty ? nil : "events"]
                                .compactMap { $0 }.joined(separator: " · "))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if expanded {
                if let pins = vm.pins { PinDiagramView(diagram: pins) }
                if let vdo = vm.vdo { VDOInspectorView(info: vdo) }
                if !vm.events.isEmpty { eventTrace }
            }
        }
    }

    private var eventTrace: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("PD EVENT TRACE").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
            FlowLayout(spacing: 4) {
                ForEach(vm.events) { e in
                    Text(e.label)
                        .font(.system(size: 9, design: .rounded).weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(eventColor(e.severity).opacity(0.2)))
                        .foregroundStyle(eventColor(e.severity))
                }
            }
        }
    }

    private func eventColor(_ s: SpeedVM.Severity) -> Color {
        switch s {
        case .good: return .green
        case .warn: return .orange
        case .info: return .blue
        case .neutral: return .secondary
        case .critical: return .red
        }
    }

    // MARK: - Cable speed panel (feature #2)

    private func speedPanel(_ sp: SpeedVM) -> some View {
        let speedColor = colorForGbps(sp.activeGbps)
        let verdictColor = color(for: sp.severity)
        return VStack(alignment: .leading, spacing: 7) {
            // Big active speed + verdict.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.subheadline).foregroundStyle(speedColor)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                Text(activeLabel(sp.activeGbps))
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(speedColor)
                    .monospacedDigit()
                Text("Gbps")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(sp.verdict)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(verdictColor.opacity(0.9)))
                    .foregroundStyle(.white)
            }
            // Mac → Cable → Device chain.
            HStack(spacing: 6) {
                chainCell("Mac", sp.hostGbps, sp.limit == .host)
                chainArrow
                chainCell("Cable", sp.cableGbps, sp.limit == .cable)
                chainArrow
                chainCell("Device", sp.deviceGbps, sp.limit == .device)
            }
            if !sp.summary.isEmpty {
                Text(sp.summary)
                    .font(.caption2)
                    .foregroundStyle(sp.isWarning ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(speedColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(speedColor.opacity(0.3), lineWidth: 1)))
    }

    private func chainCell(_ label: String, _ gbps: Double?, _ isLimit: Bool) -> some View {
        let color: Color = isLimit ? .orange : .primary
        return VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            Text(gbps.map(formatGbps) ?? "—")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isLimit ? Color.orange.opacity(0.18) : Color.white.opacity(0.06)))
    }

    private var chainArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
    }

    private func formatGbps(_ g: Double) -> String {
        g >= 1 ? "\(Int(g.rounded())) Gbps" : "\(Int((g * 1000).rounded())) Mbps"
    }

    private func activeLabel(_ g: Double) -> String {
        g >= 1 ? "\(Int(g.rounded()))" : String(format: "%.2f", g)
    }

    private func colorForGbps(_ g: Double) -> Color {
        switch g {
        case 40...: return .purple
        case 20..<40: return .green
        case 10..<20: return .teal
        case 5..<10: return .blue
        default: return .gray
        }
    }

    private func color(for severity: SpeedVM.Severity) -> Color {
        switch severity {
        case .good: return .green
        case .warn: return .orange
        case .info: return .blue
        case .neutral: return .gray
        case .critical: return .red
        }
    }

    // MARK: - PD Contract Inspector (feature #5)

    private var pdContract: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("PD PROFILES").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
            FlowChips(options: vm.pdOptions, winning: vm.pdWinning)
        }
    }

    // MARK: - CC advertisement (feature #16)

    private func ccRow(_ mA: Int) -> some View {
        let label: String
        switch mA {
        case 2900...: label = "3.0 A (Rp 3A)"
        case 1400...: label = "1.5 A (Rp 1.5A)"
        default:      label = String(format: "%.1f A (USB default)", Double(mA) / 1000)
        }
        return HStack(spacing: 5) {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text("CC advertisement").foregroundStyle(.secondary)
            Text(label).fontWeight(.semibold).foregroundStyle(.purple)
        }
        .font(.system(size: 9, design: .rounded))
    }

    // MARK: - Liquid detection (feature #11)

    private func liquidBadge(_ l: LiquidDetectionStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.triangle.fill").foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("Liquid detected").font(.system(.caption, design: .rounded).weight(.bold))
                Text(l.mitigationsEnabled ? "Charging paused for safety — dry the port"
                                          : "Check this port")
                    .font(.caption2).opacity(0.9)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.85)))
    }

    // MARK: - Port health counters (feature #7)

    private var healthRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                if let a = vm.health.attach { healthStat("arrow.down.circle", "\(a)", "attach") }
                if let d = vm.health.detach { healthStat("arrow.up.circle", "\(d)", "detach") }
                if vm.health.attach == nil, let p = vm.health.plugEvents {
                    healthStat("bolt.horizontal", "\(p)", "plugs")
                }
                if let c = vm.health.connections { healthStat("cable.connector", "\(c)", "links") }
                if let o = vm.health.overcurrent, o > 0 {
                    healthStat("exclamationmark.triangle", "\(o)", "overcurrent", color: .orange)
                }
            }
            let faults = vm.health.faults
            if !faults.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(faults.enumerated()), id: \.offset) { _, f in
                        healthStat("exclamationmark.triangle.fill", "\(f.count)", f.label, color: .orange)
                    }
                }
            }
        }
        .font(.system(size: 9))
    }

    private func healthStat(_ symbol: String, _ value: String, _ label: String,
                            color: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(value).fontWeight(.semibold)
            Text(label)
        }
        .foregroundStyle(color)
    }

    private var icon: some View {
        Image(systemName: s.status.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isEmpty ? Color.secondary : accent)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(isEmpty ? 0.08 : 0.16))
            )
    }
}
