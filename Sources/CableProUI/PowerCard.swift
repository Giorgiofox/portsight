import SwiftUI
import Charts
import WhatCableCore

// Hero card: live system power with a Swift Charts sparkline (feature C).
struct PowerCard: View {
    let power: PowerMonitorSnapshot?
    let samples: [PowerPoint]
    let adapterWatts: Int?
    var battery: BatteryVM? = nil
    var resistance: ResistanceVM? = nil

    private var onBattery: Bool { power?.onBattery ?? false }
    private var accent: Color { onBattery ? .yellow : .green }

    private var watts: Double { Double(power?.activePowerMW ?? 0) / 1000 }
    private var volts: Double { Double(power?.activeVoltageMV ?? 0) / 1000 }
    private var amps: Double { Double(power?.activeCurrentMA ?? 0) / 1000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(onBattery ? "System Power Out" : "System Power In",
                      systemImage: "waveform.path.ecg")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                sourcePill
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(power == nil ? "—" : String(format: "%.1f", watts))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: watts))
                Text("W")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if power != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.2f V", volts))
                        Text(String(format: "%.2f A", amps))
                    }
                    .font(.system(.callout, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }

            if let bat = battery {
                batteryBlock(bat)
            }

            chart

            if let r = resistance {
                resistanceRow(r)
            }
        }
        .padding(16)
        .cardSurface()
    }

    // MARK: - Battery block (merged into the power card)

    private func batteryBlock(_ bat: BatteryVM) -> some View {
        let c: Color = bat.fullyCharged ? .teal : (bat.isCharging ? .green : .yellow)
        return VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.4)
            HStack(spacing: 8) {
                Image(systemName: bat.isCharging ? "bolt.fill" : "battery.75")
                    .font(.caption).foregroundStyle(c)
                Text("\(bat.soc)%")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(c).frame(width: geo.size.width * CGFloat(bat.soc) / 100)
                    }
                }
                .frame(height: 6)
                Text(String(format: "%+.1f W", bat.signedWatts))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit().foregroundStyle(c)
            }
            batteryETA(bat, accent: c)
        }
    }

    @ViewBuilder private func batteryETA(_ bat: BatteryVM, accent: Color) -> some View {
        HStack(spacing: 6) {
            if bat.fullyCharged {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
                Text("Fully charged")
            } else if bat.isCharging {
                Image(systemName: "bolt.fill").foregroundStyle(accent)
                if let f = bat.minutesToFull {
                    Text("Full in \(fmt(f))").fontWeight(.semibold).foregroundStyle(accent)
                    if let e = bat.minutesTo80 {
                        Text("· 80% in \(fmt(e))").foregroundStyle(.secondary)
                    }
                } else {
                    Text("Charging…").foregroundStyle(accent)
                }
            } else if let e = bat.minutesToEmpty {
                Image(systemName: "hourglass").foregroundStyle(accent)
                Text("\(fmt(e)) left").fontWeight(.semibold).foregroundStyle(accent)
            } else {
                Image(systemName: "hourglass").foregroundStyle(.secondary)
                Text("estimating…").foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let pm = bat.pmsetMinutes {
                Text("macOS \(fmt(pm))").foregroundStyle(.tertiary)
            }
        }
        .font(.system(.caption, design: .rounded)).monospacedDigit()
    }

    private func fmt(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h)h \(m)m"
    }

    private var sourcePill: some View {
        HStack(spacing: 4) {
            Image(systemName: onBattery ? "battery.75" : "bolt.fill")
            Text(onBattery ? "On battery"
                 : (adapterWatts.map { "Charger · \($0)W" } ?? "Charger"))
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(accent.opacity(0.18)))
        .foregroundStyle(accent)
    }

    @ViewBuilder private var chart: some View {
        let peak = max(samples.map(\.watts).max() ?? 1, Double(adapterWatts ?? 0), 1)
        // Plot by position with a FIXED x-domain so the history builds up
        // left→right (fills the window over ~4 min) instead of a fast scroll.
        Chart(Array(samples.enumerated()), id: \.offset) { i, pt in
            AreaMark(x: .value("t", i), y: .value("W", pt.watts))
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", i), y: .value("W", pt.watts))
                .interpolationMethod(.monotone)
                .foregroundStyle(accent)
                .lineStyle(.init(lineWidth: 2))
        }
        .chartXScale(domain: 0...Double(powerSampleCap))
        .chartYScale(domain: 0...(peak * 1.15))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 64)
        .overlay(alignment: .center) {
            if samples.isEmpty {
                Text("collecting samples…")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func resistanceRow(_ r: ResistanceVM) -> some View {
        let (text, color): (String, Color) = {
            switch r.phase {
            case .notCharging:      return ("plug in charger to measure", .secondary)
            case .measuring(let n): return ("measuring… (\(n)/\(ResistanceVM.target))", .yellow)
            case .needsLoad:        return ("needs a varying charge load", .orange)
            case .stable:           return (String(format: "~%.0f mΩ", r.milliohms), .green)
            case .approx:           return (String(format: "~%.0f mΩ (approx)", r.milliohms), .yellow)
            case .unreliable:       return ("not reliably measurable on this Mac", .secondary)
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: "wave.3.right")
            Text("Cable resistance")
            Spacer()
            Text(text).foregroundStyle(color).monospacedDigit()
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(.secondary)
    }
}
