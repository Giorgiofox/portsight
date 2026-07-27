import SwiftUI

public struct ContentView: View {
    @ObservedObject var model: SnapshotModel
    var live: Bool = true
    var scroll: Bool = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var showPorts = true
    @State private var showDisplays = true
    @State private var showChargers = true
    @Environment(\.openWindow) private var openWindow

    public init(model: SnapshotModel, live: Bool = true, scroll: Bool = true) {
        self.model = model
        self.live = live
        self.scroll = scroll
    }

    public var body: some View {
        ZStack {
            Theme.backdrop
            if scroll {
                ScrollView { content.padding(14) }
            } else {
                content.padding(14)
            }
        }
        // Live popover is a fixed size (ScrollView handles overflow); the
        // no-scroll path (preview) sizes to its content instead.
        .frame(width: 460)
        .frame(height: scroll ? 620 : nil, alignment: .top)
        .onAppear { if live { model.start() } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            PowerCard(power: model.power,
                      samples: model.samples,
                      adapterWatts: model.adapterWatts,
                      battery: model.battery,
                      resistance: model.resistance)

            section("Ports", count: model.ports.count, expanded: $showPorts,
                    accessory: model.isConnected ? AnyView(activeTag) : nil) {
                ForEach(model.ports) { port in
                    PortCard(vm: port, livePower: port.portKey.flatMap { model.portPower[$0] })
                }
            }

            if !model.displays.isEmpty {
                section("Displays", count: model.displays.count, expanded: $showDisplays) {
                    ForEach(model.displays) { DisplayCard(display: $0) }
                }
            }

            // Only the charger(s) in use now — the full catalog lives in the dashboard.
            if !chargersInUse.isEmpty {
                section("Charger", count: chargersInUse.count, expanded: $showChargers) {
                    ForEach(chargersInUse) { rec in
                        ChargerMiniRow(record: rec, isConnected: true)
                    }
                }
            }

            HStack(spacing: 8) {
                openButton("Dashboard", "chart.xyaxis.line", "dashboard")
                openButton("Power Monitor", "bolt.fill", "power-monitor")
            }
            .padding(.top, 4)
            footer
        }
    }

    private var chargersInUse: [ChargerRecord] {
        model.cableStore.allChargers.filter { $0.fingerprint == model.connectedChargerKey }
    }

    private var activeTag: some View {
        Label("Active", systemImage: "circle.fill")
            .font(.caption2).foregroundStyle(.green)
            .labelStyle(.titleAndIcon).imageScale(.small)
    }

    // A collapsible section: tappable header (chevron + title + count) over content.
    @ViewBuilder private func section<Content: View>(
        _ title: String, count: Int, expanded: Binding<Bool>,
        accessory: AnyView? = nil, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(title).font(.system(.headline, design: .rounded))
                    Chip(text: "\(count)", color: .secondary)
                    Spacer()
                    if let accessory { accessory }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded.wrappedValue { content() }
        }
        .padding(.top, 2)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cable.connector.horizontal")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("PortSight")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("USB-C diagnostics")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            LiveDot(date: model.lastUpdate)
        }
    }

    private func openButton(_ title: String, _ symbol: String, _ id: String) -> some View {
        Button {
            openWindow(id: id)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title).fontWeight(.semibold)
            }
            .font(.system(.callout, design: .rounded))
            .padding(.vertical, 9).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.accentColor.opacity(0.18)))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        // Custom controls (not system Toggle/Button styles): they render
        // correctly both live and in offscreen ImageRenderer screenshots.
        HStack(spacing: 10) {
            Button {
                launchAtLogin.toggle()
                LoginItem.setEnabled(launchAtLogin)
                launchAtLogin = LoginItem.isEnabled   // reflect actual state
            } label: {
                HStack(spacing: 6) {
                    miniSwitch(on: launchAtLogin)
                    Text("Launch at login").font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { NSApplication.shared.terminate(nil) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func miniSwitch(on: Bool) -> some View {
        Capsule()
            .fill(on ? Color.green : Color.white.opacity(0.18))
            .frame(width: 26, height: 15)
            .overlay(
                Circle().fill(.white).padding(2)
                    .frame(width: 15, height: 15)
                    .offset(x: on ? 5.5 : -5.5)
            )
    }
}

// Compact charger row for the popover (full detail lives in the dashboard).
struct ChargerMiniRow: View {
    let record: ChargerRecord
    var isConnected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isConnected ? .green : .orange)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((isConnected ? Color.green : .orange).opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.displayName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    if isConnected {
                        Text("IN USE")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green)).foregroundStyle(.black)
                    }
                }
                Text(record.descriptor).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(String(format: "%.3f kWh", record.totalEnergyKWh))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit().foregroundStyle(.green)
        }
        .padding(12)
        .cardSurface(stroke: isConnected ? Color.green.opacity(0.6) : Theme.cardStroke)
    }
}

// Freshness indicator: a pulsing dot plus the time of the last update, so it
// actually tells you the data is current (and when it last refreshed).
struct LiveDot: View {
    let date: Date?
    @State private var pulse = false

    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(date != nil ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
                .scaleEffect(pulse ? 1.0 : 0.7)
                .opacity(pulse ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
            Text(date.map { "Updated \(Self.formatter.string(from: $0))" } ?? "Starting…")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onAppear { pulse = true }
    }
}
