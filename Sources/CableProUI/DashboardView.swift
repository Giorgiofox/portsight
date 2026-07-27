import SwiftUI
import Charts

// The "real app" window: live power dashboard + persistent per-cable statistics.
public struct DashboardView: View {
    @ObservedObject var model: SnapshotModel
    @ObservedObject var store: CableStore
    var live: Bool = true
    var scroll: Bool = true

    public init(model: SnapshotModel, live: Bool = true, scroll: Bool = true) {
        self.model = model
        self.store = model.cableStore
        self.live = live
        self.scroll = scroll
    }

    public var body: some View {
        ZStack {
            Theme.backdrop
            if scroll {
                ScrollView { content.padding(20) }
            } else {
                content.padding(20)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .onAppear { if live { model.start() } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statsRow
            powerChartCard
            energyChartCard
            cablesSection
            chargersSection
        }
    }

    // MARK: header + global stats

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView().frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("PortSight").font(.system(.title, design: .rounded).weight(.bold))
                Text("Live diagnostics & cable statistics")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            LiveDot(date: model.lastUpdate)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard("Energy delivered", String(format: "%.3f", store.totalEnergyKWh), "kWh",
                     "bolt.fill", .green)
            statCard("Cables tracked", "\(store.records.count)", "catalogued",
                     "cable.connector.horizontal", .blue)
            statCard("Live power",
                     model.power.map { String(format: "%.1f", Double($0.activePowerMW) / 1000) } ?? "—",
                     "W now", "waveform.path.ecg", .teal)
            statCard("Ports active", "\(model.ports.filter { $0.speed != nil }.count)", "with data",
                     "app.connected.to.app.below.fill", .purple)
        }
    }

    private func statCard(_ title: String, _ value: String, _ unit: String,
                          _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(color)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface()
    }

    // MARK: live power chart

    private var powerChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System power").font(.system(.headline, design: .rounded))
            let peak = max(model.samples.map(\.watts).max() ?? 1, Double(model.adapterWatts ?? 0), 1)
            Chart(Array(model.samples.enumerated()), id: \.offset) { i, pt in
                AreaMark(x: .value("t", i), y: .value("W", pt.watts))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [.green.opacity(0.35), .green.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", i), y: .value("W", pt.watts))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.green).lineStyle(.init(lineWidth: 2))
            }
            .chartXScale(domain: 0...Double(max(model.samples.count - 1, 1)))
            .chartYScale(domain: 0...(peak * 1.15))
            .chartXAxis(.hidden)
            .frame(height: 180)
            .overlay(alignment: .center) {
                if model.samples.isEmpty {
                    Text("collecting samples…").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .cardSurface()
    }

    // MARK: per-cable statistics

    // Currently-connected cables first, then by energy delivered.
    private var sortedCables: [CableRecord] {
        store.all.sorted { a, b in
            let ca = model.connectedCableKeys.contains(a.fingerprint)
            let cb = model.connectedCableKeys.contains(b.fingerprint)
            if ca != cb { return ca }
            return a.totalEnergyWh > b.totalEnergyWh
        }
    }

    private var cablesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cables").font(.system(.headline, design: .rounded))
                Chip(text: "\(store.records.count)", color: .secondary)
                Spacer()
            }
            if store.all.isEmpty {
                Text("No e-markered cables catalogued yet. Plug in a charging cable with an e-marker chip and its stats will accumulate here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).cardSurface()
            } else {
                ForEach(sortedCables) { rec in
                    CableRow(record: rec, store: store,
                             isConnected: model.connectedCableKeys.contains(rec.fingerprint))
                }
            }
        }
    }

    // MARK: energy delivered (cables + chargers)

    struct EnergyBar: Identifiable {
        let id: String
        let label: String
        let kWh: Double
        let isCharger: Bool
    }

    private var energyBars: [EnergyBar] {
        let cables = store.all.map {
            EnergyBar(id: "cable-\($0.fingerprint)", label: $0.displayName,
                      kWh: $0.totalEnergyKWh, isCharger: false)
        }
        let chargers = store.allChargers.map {
            EnergyBar(id: "charger-\($0.fingerprint)", label: $0.displayName,
                      kWh: $0.totalEnergyKWh, isCharger: true)
        }
        return (cables + chargers).sorted { $0.kWh > $1.kWh }
    }

    @ViewBuilder private var energyChartCard: some View {
        if !energyBars.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Energy delivered").font(.system(.headline, design: .rounded))
                    legendDot(.green, "cables"); legendDot(.orange, "chargers")
                    Spacer()
                }
                Chart(energyBars) { bar in
                    BarMark(x: .value("kWh", bar.kWh), y: .value("Source", bar.label))
                        .foregroundStyle((bar.isCharger ? Color.orange : .green).gradient)
                        .annotation(position: .trailing) {
                            Text(String(format: "%.3f", bar.kWh))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartXAxisLabel("kWh")
                .frame(height: CGFloat(energyBars.count) * 32 + 30)
            }
            .padding(16).cardSurface()
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: per-charger statistics

    private var sortedChargers: [ChargerRecord] {
        store.allChargers.sorted { a, b in
            let ca = a.fingerprint == model.connectedChargerKey
            let cb = b.fingerprint == model.connectedChargerKey
            if ca != cb { return ca }
            return a.totalEnergyWh > b.totalEnergyWh
        }
    }

    @ViewBuilder private var chargersSection: some View {
        if !store.allChargers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Chargers").font(.system(.headline, design: .rounded))
                    Chip(text: "\(store.chargers.count)", color: .secondary)
                    Spacer()
                }
                ForEach(sortedChargers) { rec in
                    ChargerRow(record: rec, store: store,
                               isConnected: rec.fingerprint == model.connectedChargerKey)
                }
            }
        }
    }
}

// One charger's stats row.
struct ChargerRow: View {
    let record: ChargerRecord
    @ObservedObject var store: CableStore
    var isConnected: Bool = false
    @State private var renaming = false
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "powerplug.fill")
                    .foregroundStyle(isConnected ? .green : .orange)
                Text(record.displayName).font(.system(.headline, design: .rounded))
                if isConnected {
                    Text("IN USE NOW")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green))
                        .foregroundStyle(.black)
                }
                Spacer()
                Button { draftName = record.name ?? ""; renaming = true } label: {
                    iconChip("pencil", .secondary)
                }.buttonStyle(.plain)
                if !isConnected {
                    Button { store.forgetCharger(record.fingerprint) } label: {
                        iconChip("trash", .red)
                    }.buttonStyle(.plain)
                }
            }
            if !record.descriptor.isEmpty {
                Text(record.descriptor).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                stat("bolt.fill", String(format: "%.3f kWh", record.totalEnergyKWh), .green)
                stat("repeat", "\(record.sessionCount) sessions", .secondary)
                stat("gauge.high", String(format: "%.0f W peak", record.peakWatts), .orange)
                stat("clock", connectedLabel, .secondary)
            }
            .font(.system(.caption, design: .rounded))
        }
        .padding(14)
        .cardSurface(stroke: isConnected ? Color.green.opacity(0.65) : Theme.cardStroke)
        .alert("Rename charger", isPresented: $renaming) {
            TextField("Nickname", text: $draftName)
            Button("Save") { store.renameCharger(record.fingerprint, to: draftName) }
            Button("Cancel", role: .cancel) {}
        } message: { Text(record.label) }
    }

    private func stat(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func iconChip(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.caption).foregroundStyle(color)
            .frame(width: 26, height: 22)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
    }

    private var connectedLabel: String {
        let s = Int(record.connectedSeconds)
        if s < 3600 { return "\(s / 60)m connected" }
        return "\(s / 3600)h \(s % 3600 / 60)m connected"
    }
}

// One cable's detailed stats row, with rename/forget.
struct CableRow: View {
    let record: CableRecord
    @ObservedObject var store: CableStore
    var isConnected: Bool = false
    @State private var renaming = false
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundStyle(isConnected ? .green : .blue)
                Text(record.displayName).font(.system(.headline, design: .rounded))
                if isConnected {
                    Text("IN USE NOW")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green))
                        .foregroundStyle(.black)
                } else if record.name != nil {
                    Text(record.vendorName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { draftName = record.name ?? ""; renaming = true } label: {
                    iconChip("pencil", .secondary)
                }.buttonStyle(.plain)
                if !isConnected {
                    Button { store.forget(record.fingerprint) } label: {
                        iconChip("trash", .red)
                    }.buttonStyle(.plain)
                }
            }
            if !record.descriptor.isEmpty {
                Text(record.descriptor).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                stat("bolt.fill", String(format: "%.3f kWh", record.totalEnergyKWh), .green)
                stat("repeat", "\(record.connectionCount) sessions", .secondary)
                stat("gauge.high", String(format: "%.0f W peak", record.peakWatts), .orange)
                if record.maxSpeedGbps >= 1 {
                    stat("speedometer", "\(Int(record.maxSpeedGbps.rounded())) Gbps max", .purple)
                } else {
                    stat("bolt.fill", "charge-only", .secondary)
                }
                stat("clock", connectedLabel, .secondary)
            }
            .font(.system(.caption, design: .rounded))
        }
        .padding(14)
        .cardSurface(stroke: isConnected ? Color.green.opacity(0.65) : Theme.cardStroke)
        .alert("Rename cable", isPresented: $renaming) {
            TextField("Nickname", text: $draftName)
            Button("Save") { store.rename(record.fingerprint, to: draftName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(record.vendorName)
        }
    }

    private func stat(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func iconChip(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .frame(width: 26, height: 22)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
    }

    private var connectedLabel: String {
        let s = Int(record.connectedSeconds)
        if s < 3600 { return "\(s / 60)m connected" }
        return "\(s / 3600)h \(s % 3600 / 60)m connected"
    }
}
