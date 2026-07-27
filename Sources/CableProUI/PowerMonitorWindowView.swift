import SwiftUI
import Charts

// Dedicated, detachable Power Monitor window (feature #12): a focused live view
// of system power with a large chart and big readouts.
public struct PowerMonitorWindowView: View {
    @ObservedObject var model: SnapshotModel
    var live: Bool = true

    public init(model: SnapshotModel, live: Bool = true) {
        self.model = model
        self.live = live
    }

    private var onBattery: Bool { model.power?.onBattery ?? false }
    private var accent: Color { onBattery ? .yellow : .green }
    private var watts: Double { Double(model.power?.activePowerMW ?? 0) / 1000 }
    private var volts: Double { Double(model.power?.activeVoltageMV ?? 0) / 1000 }
    private var amps: Double { Double(model.power?.activeCurrentMA ?? 0) / 1000 }

    public var body: some View {
        ZStack {
            Theme.backdrop
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(onBattery ? "Power Out" : "Power In", systemImage: "bolt.fill")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(accent)
                    Spacer()
                    Text(onBattery ? "On battery"
                         : (model.adapterWatts.map { "Charger · \($0) W" } ?? "Charger"))
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.18)))
                        .foregroundStyle(accent)
                }

                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    readout(String(format: "%.1f", watts), "W", accent)
                    readout(String(format: "%.2f", volts), "V", .secondary)
                    readout(String(format: "%.2f", amps), "A", .secondary)
                }

                chart

                if let r = model.resistance, case .stable = r.phase {
                    Label(String(format: "Cable resistance ≈ %.0f mΩ", r.milliohms),
                          systemImage: "wave.3.right")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { if live { model.start() } }
    }

    private func readout(_ value: String, _ unit: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value) ?? 0))
            Text(unit).font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var chart: some View {
        let peak = max(model.samples.map(\.watts).max() ?? 1, Double(model.adapterWatts ?? 0), 1)
        Chart(Array(model.samples.enumerated()), id: \.offset) { i, pt in
            AreaMark(x: .value("t", i), y: .value("W", pt.watts))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", i), y: .value("W", pt.watts))
                .interpolationMethod(.monotone)
                .foregroundStyle(accent).lineStyle(.init(lineWidth: 2.5))
        }
        .chartXScale(domain: 0...Double(powerSampleCap))
        .chartYScale(domain: 0...(peak * 1.15))
        .chartXAxis(.hidden)
        .frame(minHeight: 220)
        .overlay(alignment: .center) {
            if model.samples.isEmpty {
                Text("collecting samples…").font(.callout).foregroundStyle(.tertiary)
            }
        }
    }
}
