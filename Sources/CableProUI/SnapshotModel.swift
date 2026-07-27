import SwiftUI
import WhatCableCore
import WhatCableDarwinBackend

// One data point on the power chart.
struct PowerPoint: Identifiable, Equatable {
    let id: Int
    let watts: Double
}

// Battery charge/discharge estimates. Plain data holder — all predictions are
// computed by SnapshotModel.BatteryEstimator from a smoothed current window.
struct BatteryVM: Equatable {
    let soc: Int                 // state of charge, 0–100
    let isCharging: Bool
    let externalConnected: Bool
    let fullyCharged: Bool
    let minutesToFull: Int?      // to 100% (our estimate)
    let minutesTo80: Int?        // to 80% (our estimate)
    let minutesToEmpty: Int?     // battery life (our estimate)
    let watts: Double            // smoothed charge/discharge power magnitude
    var pmsetMinutes: Int? = nil // macOS's own estimate, shown as a cross-reference

    /// Signed power: positive while charging (into the battery), negative while
    /// discharging (out of the battery).
    var signedWatts: Double { isCharging ? watts : -watts }
    var isDischarging: Bool { !externalConnected }
}

// Physically-grounded battery predictor: remaining charge ÷ smoothed current.
// Keeps a rolling window of recent current samples so the estimate is stable
// (not the noisy instantaneous reading) and independent of macOS's opaque one.
@MainActor
final class BatteryEstimator {
    private var currentWindowMA: [Double] = []   // signed: + charging, − discharging
    private let windowCap = 90                    // ~90 s at 1 Hz

    func update(_ b: AppleSmartBattery, pmset: PmsetInfo?) -> BatteryVM? {
        guard b.batteryInstalled else { currentWindowMA.removeAll(); return nil }

        let soc = min(100, max(0, b.maxCapacity > 0
            ? Int((Double(b.currentCapacity) / Double(b.maxCapacity) * 100).rounded())
            : b.currentCapacity))

        // Signed instantaneous current (mA): negative = discharge, positive = charge.
        let inst = Double(b.instantAmperage != 0 ? b.instantAmperage : b.amperage)
        currentWindowMA.append(inst)
        if currentWindowMA.count > windowCap { currentWindowMA.removeFirst(currentWindowMA.count - windowCap) }
        let avgMA = currentWindowMA.reduce(0, +) / Double(currentWindowMA.count)

        let fullMAh = Double(b.rawMaxCapacity)
        let nowMAh = Double(b.rawCurrentCapacity)
        let voltage = Double(b.voltage)          // mV
        let watts = voltage * abs(avgMA) / 1_000_000

        var toEmpty: Int?, toFull: Int?, to80: Int?
        if !b.externalConnected {
            // Discharging: remaining charge ÷ average draw.
            let drawMA = abs(min(avgMA, -1))     // guard tiny/zero
            if drawMA > 5, nowMAh > 0 { toEmpty = Int((nowMAh / drawMA * 60).rounded()) }
        } else if b.isCharging {
            // Charging: (target − now) ÷ average charge current. Linear on charge,
            // so slightly optimistic in the CV tail near 100% — stated as an estimate.
            let chargeMA = max(avgMA, 1)
            if chargeMA > 5, fullMAh > 0 {
                if fullMAh > nowMAh { toFull = Int(((fullMAh - nowMAh) / chargeMA * 60).rounded()) }
                let mAh80 = 0.80 * fullMAh
                if soc < 80, mAh80 > nowMAh { to80 = Int(((mAh80 - nowMAh) / chargeMA * 60).rounded()) }
            }
        }

        return BatteryVM(
            soc: soc, isCharging: b.isCharging, externalConnected: b.externalConnected,
            fullyCharged: b.fullyCharged, minutesToFull: toFull, minutesTo80: to80,
            minutesToEmpty: toEmpty, watts: watts, pmsetMinutes: pmset?.minutesRemaining)
    }
}

// Negotiated link-speed panel (feature #2) — the "cable speed" highlight.
struct SpeedVM: Equatable {
    enum Limit { case host, cable, device, none }
    enum Severity { case good, warn, info, neutral, critical }

    let activeGbps: Double
    let hostGbps: Double?
    let cableGbps: Double?
    let deviceGbps: Double?
    let limit: Limit
    let verdict: String
    let severity: Severity
    let summary: String
    let isWarning: Bool

    var hasChain: Bool { hostGbps != nil || cableGbps != nil || deviceGbps != nil }

    init(_ dl: DataLinkDiagnostic) {
        activeGbps = dl.facts.activeGbps
        hostGbps = dl.facts.hostGbps
        cableGbps = dl.facts.cableGbps
        deviceGbps = dl.facts.deviceGbps
        summary = dl.summary
        isWarning = dl.isWarning
        switch dl.bottleneck {
        case .fine:                  limit = .none;   verdict = "Full speed";     severity = .good
        case .cableLimit:            limit = .cable;  verdict = "Cable limits";   severity = .warn
        case .cableContradictsActive:limit = .cable;  verdict = "Cable mismatch"; severity = .warn
        case .hostLimit:             limit = .host;   verdict = "Mac port limit"; severity = .info
        case .deviceLimit:           limit = .device; verdict = "Device limit";   severity = .neutral
        case .degraded:              limit = .none;   verdict = "Degraded";       severity = .warn
        case .unknownCable:          limit = .none;   verdict = "Cable unrated";  severity = .neutral
        case .blockedBySecurity:     limit = .none;   verdict = "Approve device"; severity = .critical
        }
    }

    init(activeGbps: Double, hostGbps: Double?, cableGbps: Double?, deviceGbps: Double?,
         limit: Limit, verdict: String, severity: Severity, summary: String, isWarning: Bool) {
        self.activeGbps = activeGbps; self.hostGbps = hostGbps
        self.cableGbps = cableGbps; self.deviceGbps = deviceGbps
        self.limit = limit; self.verdict = verdict; self.severity = severity
        self.summary = summary; self.isWarning = isWarning
    }
}

// Lifetime health counters for a port. Basic fields come from AppleHPMInterface;
// the rich fault counters come from PortDiagnostics (PortHealthCounters).
struct PortHealth: Equatable {
    // Basic (always available)
    let plugEvents: Int?
    let connections: Int?
    let overcurrent: Int?
    // Rich (from PortDiagnostics, when the diagnostics watcher has data)
    var attach: Int?
    var detach: Int?
    var hardResets: Int?
    var shorts: Int?
    var i2cErrors: Int?
    var roleSwaps: Int?       // data + power role swaps combined
    var fetFailures: Int?

    var hasAny: Bool {
        (plugEvents ?? 0) + (connections ?? 0) + (overcurrent ?? 0) + (attach ?? 0) + (detach ?? 0) > 0
    }

    /// Fault counters worth flagging (non-zero → shown, coloured).
    var faults: [(label: String, count: Int)] {
        [("hard resets", hardResets ?? 0), ("shorts", shorts ?? 0),
         ("I²C errors", i2cErrors ?? 0), ("role swaps", roleSwaps ?? 0),
         ("FET fails", fetFailures ?? 0)].filter { $0.count > 0 }
    }

    init(plugEvents: Int?, connections: Int?, overcurrent: Int?) {
        self.plugEvents = plugEvents
        self.connections = connections
        self.overcurrent = overcurrent
    }

    // Preview convenience.
    init(plugEvents: Int?, connections: Int?, overcurrent: Int?, attach: Int?, detach: Int?,
         hardResets: Int? = 0, shorts: Int? = 0, i2cErrors: Int? = 0,
         roleSwaps: Int? = 0, fetFailures: Int? = 0) {
        self.plugEvents = plugEvents; self.connections = connections
        self.overcurrent = overcurrent
        self.attach = attach; self.detach = detach
        self.hardResets = hardResets; self.shorts = shorts
        self.i2cErrors = i2cErrors; self.roleSwaps = roleSwaps
        self.fetFailures = fetFailures
    }

    /// Merge in rich counters from PortDiagnostics.
    mutating func merge(_ c: PortHealthCounters) {
        attach = c.attachCount
        detach = c.detachCount
        hardResets = c.hardResetCount
        shorts = c.shortDetectCount
        i2cErrors = c.i2cErrCount
        roleSwaps = c.dataRoleSwapCount + c.pwrRoleSwapCount
        fetFailures = c.fetEnableFailCount
    }
}

// An external display ready to render as a card (feature #3).
struct DisplayVM: Identifiable, Equatable {
    let id: Int
    let title: String
    let modeLabel: String?       // active resolution/refresh
    let lanes: Int
    let maxLanes: Int
    let deliveredGbps: Double?
    let rateDescription: String?
    let summary: String
    let isWarning: Bool

    init(_ d: DisplayDiagnostic, id: Int) {
        self.id = id
        self.title = d.facts.monitorName ?? "External display"
        self.modeLabel = d.facts.currentMode?.label
        self.lanes = d.facts.lanes
        self.maxLanes = d.facts.maxLanes
        self.deliveredGbps = d.facts.deliveredGbps
        self.rateDescription = d.facts.rateDescription
        self.summary = d.summary
        self.isWarning = d.isWarning
    }

    // Memberwise init for previews.
    init(id: Int, title: String, modeLabel: String?, lanes: Int, maxLanes: Int,
         deliveredGbps: Double?, rateDescription: String?, summary: String, isWarning: Bool) {
        self.id = id; self.title = title; self.modeLabel = modeLabel
        self.lanes = lanes; self.maxLanes = maxLanes
        self.deliveredGbps = deliveredGbps; self.rateDescription = rateDescription
        self.summary = summary; self.isWarning = isWarning
    }
}

// Live per-port power (feature #4), when the controller meters it.
struct PortLivePower: Equatable {
    let watts: Double
    let volts: Double
    let amps: Double
}

// A port ready to render as a card.
struct PortVM: Identifiable {
    let id: UInt64
    let portKey: String?
    let title: String
    let type: String?
    let summary: PortSummary
    let speed: SpeedVM?
    let health: PortHealth
    let pdOptions: [PowerOption]
    let pdWinning: PowerOption?
    var liquid: LiquidDetectionStatus? = nil
    var pins: PinDiagramVM? = nil
    var vdo: VDOInfo? = nil
    var events: [PortEventVM] = []
    var ccAdvertMA: Int? = nil    // Type-C Rp advertised current at 5V (feature #16)
}

// One decoded PD protocol event (feature #8).
struct PortEventVM: Identifiable, Equatable {
    let id: Int
    let label: String
    let severity: SpeedVM.Severity
}

/// Number of power samples retained/plotted. At 1 Hz this is the width of the
/// live chart's time window; the chart fills left→right until it's reached.
let powerSampleCap = 240   // ~4 minutes

// Cable resistance estimate (our own, system-level). WhatCable's per-port
// regression needs per-port telemetry that laptops don't expose, so instead we
// regress the charger→Mac voltage drop (negotiatedV − systemV) against system
// input current. The slope is the series resistance.
struct ResistanceVM: Equatable {
    enum Phase: Equatable { case notCharging, measuring(Int), needsLoad, stable, unreliable }
    let milliohms: Double
    let phase: Phase
    let sampleCount: Int
    static let target = 40
}

@MainActor
final class ResistanceEstimator {
    private struct S { let i: Double; let v: Double }  // current mA, drop mV
    private var win: [S] = []
    private let cap = 240
    private var lastNegotiated = 0
    private let minSamples = 15
    private let minSpreadMA = 120.0

    func update(negotiatedMV: Int, systemVoltageInMV: Int, systemCurrentInMA: Int, charging: Bool) -> ResistanceVM {
        guard charging else { win.removeAll(); return ResistanceVM(milliohms: 0, phase: .notCharging, sampleCount: 0) }
        if negotiatedMV != lastNegotiated { win.removeAll(); lastNegotiated = negotiatedMV }

        let drop = Double(negotiatedMV - systemVoltageInMV)
        if negotiatedMV > 0, systemCurrentInMA > 30, drop > 0 {
            win.append(S(i: Double(systemCurrentInMA), v: drop))
            if win.count > cap { win.removeFirst(win.count - cap) }
        }
        let n = win.count
        if n < minSamples { return ResistanceVM(milliohms: 0, phase: .measuring(n), sampleCount: n) }

        let currents = win.map(\.i)
        let spread = (currents.max() ?? 0) - (currents.min() ?? 0)
        if spread < minSpreadMA { return ResistanceVM(milliohms: 0, phase: .needsLoad, sampleCount: n) }

        // Least-squares fit: drop = slope·current + intercept. slope (mV/mA) = Ω.
        let cnt = Double(n)
        let mi = currents.reduce(0, +) / cnt
        let mv = win.map(\.v).reduce(0, +) / cnt
        let sii = win.reduce(0) { $0 + pow($1.i - mi, 2) }
        guard sii > 0 else { return ResistanceVM(milliohms: 0, phase: .needsLoad, sampleCount: n) }
        let siv = win.reduce(0) { $0 + ($1.i - mi) * ($1.v - mv) }
        let slope = siv / sii
        let intercept = mv - slope * mi
        let total = win.reduce(0) { $0 + pow($1.v - mv, 2) }
        let residual = win.reduce(0) { let p = slope * $1.i + intercept; return $0 + pow($1.v - p, 2) }
        let r2 = total > 0 ? max(0, 1 - residual / total) : 0
        let mOhm = max(0, slope * 1000)   // mV/mA → mΩ

        let phase: ResistanceVM.Phase
        if n < ResistanceVM.target { phase = .measuring(n) }
        else if r2 >= 0.7 { phase = .stable }
        else { phase = .unreliable }
        return ResistanceVM(milliohms: mOhm, phase: phase, sampleCount: n)
    }
}

@MainActor
public final class SnapshotModel: ObservableObject {
    @Published private(set) var ports: [PortVM] = []
    @Published private(set) var power: PowerMonitorSnapshot?
    @Published private(set) var samples: [PowerPoint] = []
    @Published private(set) var adapterWatts: Int?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isConnected = false   // any port active
    @Published private(set) var battery: BatteryVM?
    @Published private(set) var displays: [DisplayVM] = []
    @Published private(set) var portPower: [String: PortLivePower] = [:]
    @Published private(set) var resistance: ResistanceVM?

    /// Persistent per-cable statistics (energy, sessions, history).
    /// In preview/offscreen mode (Theme.flat) it's in-memory so real catalogued
    /// cables never leak into rendered screenshots.
    public let cableStore = CableStore(inMemory: Theme.flat)

    private let provider = makeDefaultSnapshotProvider()
    private let powerWatcher = PowerTelemetryWatcher()
    private let diagWatcher = PortDiagnosticsWatcher()
    private let liquidWatcher = LiquidDetectionWatcher()
    private var started = false
    private var seq = 0
    private let sampleCap = powerSampleCap

    // Energy attribution: the e-markered cable currently on the charging port.
    private var chargingCableKey: String?
    private var lastEnergyTick: Date?

    // Battery prediction (our own smoothed estimate + throttled pmset reference).
    private let batteryEstimator = BatteryEstimator()
    private var lastPmset: PmsetInfo?
    private var pmsetTick = 0

    // Cable resistance (our own system-level regression).
    private let resistanceEstimator = ResistanceEstimator()

    // Latest inputs; ports are rebuilt whenever any of these changes so the
    // separate watcher clocks (cable / diagnostics / liquid) stay merged.
    private var lastCable: CableSnapshot?
    private var lastHealth: [String: PortHealthCounters] = [:]
    private var lastEventTraces: [String: PDEventTrace] = [:]
    private var lastLiquid: [LiquidDetectionWatcher.LiquidDetectionUpdate] = []

    public init() {}

    /// Menu-bar label: shows live watts while charging, else a dash.
    public var menuBarText: String {
        guard let p = power, !p.onBattery, p.externalConnected, p.activePowerMW > 500 else { return "" }
        return "\(Int((Double(p.activePowerMW) / 1000).rounded()))W"
    }

    public func start() {
        guard !started else { return }
        started = true
        powerWatcher.start()
        diagWatcher.start()
        liquidWatcher.start()

        Task { [weak self] in
            guard let self else { return }
            do {
                for try await snap in self.provider.watch() {
                    self.lastCable = snap
                    self.rebuildPorts()
                    self.powerWatcher.updatePorts(snap.ports)
                }
            } catch {
                // Leave last-known state on screen; a transient IOKit error
                // shouldn't blank the UI.
            }
        }

        Task { [weak self] in
            guard let self else { return }
            for await diag in self.diagWatcher.snapshots {
                self.lastHealth = diag.healthCounters
                self.lastEventTraces = diag.eventTraces
                self.rebuildPorts()
            }
        }

        Task { [weak self] in
            guard let self else { return }
            // LiquidDetectionWatcher publishes via @Published; poll its value on
            // the diagnostics cadence by observing through a light timer.
            while !Task.isCancelled {
                self.lastLiquid = self.liquidWatcher.statuses
                self.rebuildPorts()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            for await snap in self.powerWatcher.snapshots {
                self.applyPower(snap)
            }
        }
    }

    private func rebuildPorts() {
        guard let snap = lastCable else { return }
        let activePortCount = snap.ports.filter { $0.connectionActive == true }.count
        let chargerSourceCount = ChargerWattageSource.chargerSourceCount(
            ports: snap.ports, sources: snap.powerSources)

        ports = snap.ports.map { port in
            let portSources = snap.powerSources.filter { $0.canonicallyMatches(port: port) }
            let wattageSource = ChargerWattageSource.resolve(
                portSources: portSources,
                activePortCount: activePortCount,
                chargerSourceCount: chargerSourceCount,
                adapter: snap.adapter
            )
            let summary = PortSummary(
                port: port,
                sources: portSources,
                identities: snap.identities.filter { $0.canonicallyMatches(port: port) },
                devices: port.matchingDevices(from: snap.usbDevices),
                thunderboltSwitches: snap.thunderboltSwitches,
                federatedIdentities: snap.federatedIdentities,
                usb3Transports: snap.usb3Transports.filter { $0.canonicallyMatches(port: port) },
                cioCapability: snap.cioCapabilities.first { $0.canonicallyMatches(port: port) },
                chargerWattageSource: wattageSource,
                batteryFullyCharged: snap.batteryFullyCharged,
                batteryIsCharging: snap.batteryIsCharging,
                adapter: snap.adapter
            )
            let speed = DataLinkDiagnostic(
                port: port,
                identities: snap.identities.filter { $0.canonicallyMatches(port: port) },
                devices: port.matchingDevices(from: snap.usbDevices),
                usb3Transports: snap.usb3Transports.filter { $0.canonicallyMatches(port: port) },
                cio: snap.cioCapabilities.first { $0.canonicallyMatches(port: port) },
                thunderboltSwitches: snap.thunderboltSwitches
            ).map(SpeedVM.init)
            var health = PortHealth(
                plugEvents: port.plugEventCount,
                connections: port.connectionCount,
                overcurrent: port.overcurrentCount
            )
            if let key = port.portKey, let counters = lastHealth[key] {
                health.merge(counters)
            }
            // Liquid: match by port type + index (best-effort).
            let liquid = lastLiquid.first {
                $0.status.liquidDetected &&
                (port.portNumber == nil || $0.portIndex == port.portNumber)
            }?.status
            // PD contract: richest matching source's PDO list + winning profile.
            let pdSource = portSources.max { $0.options.count < $1.options.count }
            // CC advertisement (#16): the "TypeC" source's Rp current at 5V.
            let ccAdvertMA = portSources.first { $0.name == "TypeC" }?
                .options.first { $0.voltageMV == 5000 }?.maxCurrentMA
            // Nerdy details (only when connected).
            let connected = port.connectionActive == true
            let pins = connected
                ? PinDiagramVM(orientation: port.plugOrientation, activeTransports: port.transportsActive)
                : nil
            let identity = snap.identities.first {
                $0.canonicallyMatches(port: port) &&
                ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime || $0.endpoint == .sop)
            }
            let vdo = identity.map(VDOInfo.init)
            let events: [PortEventVM] = (port.portKey.flatMap { lastEventTraces[$0] }?.events ?? [])
                .suffix(10).reversed().enumerated().map { i, e in
                    let (label, sev) = Self.describe(e)
                    return PortEventVM(id: i, label: label, severity: sev)
                }
            return PortVM(
                id: port.id,
                portKey: port.portKey,
                title: port.portDescription ?? port.serviceName,
                type: port.portTypeDescription,
                summary: summary,
                speed: speed,
                health: health,
                pdOptions: pdSource?.options ?? [],
                pdWinning: pdSource?.winning,
                liquid: liquid,
                pins: pins,
                vdo: vdo,
                events: events,
                ccAdvertMA: ccAdvertMA
            )
        }
        displays = snap.displayPorts.enumerated().compactMap { i, dp in
            DisplayDiagnostic(dp: dp).map { DisplayVM($0, id: i) }
        }
        adapterWatts = snap.adapter?.watts
        isConnected = activePortCount > 0
        updateChargingCable(snap)
        lastUpdate = Date()
    }

    /// Find the e-markered cable on the charging port and register it, so power
    /// ticks can attribute delivered energy to it.
    private func updateChargingCable(_ snap: CableSnapshot) {
        let chargingPort = snap.ports.first { port in
            port.connectionActive == true &&
            snap.powerSources.contains { $0.canonicallyMatches(port: port) && $0.winning != nil }
        }
        guard let port = chargingPort,
              let emarker = snap.identities.first(where: {
                  $0.canonicallyMatches(port: port) &&
                  ($0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime)
              }),
              let id = CableIdentity.make(from: emarker) else {
            chargingCableKey = nil
            return
        }
        let speedGbps = ports.first { $0.id == port.id }?.speed?.activeGbps ?? 0
        cableStore.observe(fingerprint: id.key, vendorName: id.vendor,
                           descriptor: id.descriptor, speedGbps: speedGbps, now: Date())
        chargingCableKey = id.key
    }

    /// Map a decoded PD protocol event to a compact label + severity (#8).
    static func describe(_ e: PDEvent) -> (String, SpeedVM.Severity) {
        switch e {
        case .plugInsertOrRemoval: return ("Plug", .info)
        case .prSwapComplete:      return ("PR swap", .warn)
        case .drSwapComplete:      return ("DR swap", .warn)
        case .sourceCapRx:         return ("Src caps", .neutral)
        case .statusUpdate:        return ("Status", .neutral)
        case .pdStatusUpdate:      return ("PD status", .neutral)
        case .usb2Plug:            return ("USB2", .neutral)
        case .powerStatusUpdate:   return ("Power", .good)
        case .appLoaded:           return ("Init", .good)
        case .rxIdSop:             return ("Identity", .info)
        case .uvdmStatusUpdate:    return ("uVDM", .neutral)
        case .uvdmEnum:            return ("uVDM enum", .neutral)
        case .sleepWake:           return ("Sleep/Wake", .neutral)
        case .alert:               return ("Alert", .critical)
        case .unknown(let v):      return (String(format: "0x%02X", v), .neutral)
        }
    }

    private func applyPower(_ snap: PowerMonitorSnapshot) {
        power = snap
        seq += 1
        samples.append(PowerPoint(id: seq, watts: Double(snap.activePowerMW) / 1000.0))
        if samples.count > sampleCap { samples.removeFirst(samples.count - sampleCap) }

        // Per-port live power (#4), derived from V×I so it's unit-safe.
        var pp: [String: PortLivePower] = [:]
        for s in snap.portSamples {
            let v = Double(s.adapterVoltage) / 1000
            let a = Double(s.current) / 1000
            let w = v * a
            if w > 0.2 { pp[s.portKey] = PortLivePower(watts: w, volts: v, amps: a) }
        }
        portPower = pp
        // Battery telemetry + our own smoothed prediction. pmset (a subprocess)
        // is refreshed every ~3s as a cross-reference, not every tick.
        var negotiatedMV = 0
        if let b = AppleSmartBatteryReader.read().battery {
            pmsetTick += 1
            if lastPmset == nil || pmsetTick % 3 == 0 { lastPmset = PmsetReader.read() }
            battery = batteryEstimator.update(b, pmset: lastPmset)
            negotiatedMV = b.adapterDetails?.voltageMV ?? 0
        } else {
            battery = nil
        }

        // Our own cable-resistance estimate: regress (negotiatedV − systemV)
        // drop against system input current. Works on laptops where WhatCable's
        // per-port telemetry is unavailable.
        resistance = resistanceEstimator.update(
            negotiatedMV: negotiatedMV,
            systemVoltageInMV: snap.systemSample.systemVoltageIn,
            systemCurrentInMA: snap.systemSample.systemCurrentIn,
            charging: snap.externalConnected && !snap.onBattery)

        // Attribute delivered energy to the charging cable (integrate P·dt).
        let now = Date()
        if let key = chargingCableKey, !snap.onBattery, snap.externalConnected {
            let watts = Double(snap.activePowerMW) / 1000
            if watts > 0.5, let last = lastEnergyTick {
                let dt = min(max(now.timeIntervalSince(last), 0), 5)  // clamp sleep gaps
                if dt > 0 { cableStore.accumulate(fingerprint: key, watts: watts, seconds: dt, now: now) }
            }
        }
        lastEnergyTick = now
        lastUpdate = now
    }

    /// Mock model for offscreen design previews (no live watchers).
    public static func preview() -> SnapshotModel {
        let m = SnapshotModel()
        let noHealth = PortHealth(plugEvents: nil, connections: nil, overcurrent: nil)
        m.ports = [
            PortVM(id: 1, portKey: "2/1", title: "Port-USB-C@1", type: "USB-C",
                   summary: PortSummary(
                       status: .charging,
                       headline: "Charging · 100W charger",
                       subtitle: "Power is flowing. No data connection.",
                       bullets: ["Charger advertises up to 100W",
                                 "Currently negotiated: 20V @ 5.00A (100W)",
                                 "Cable has an e-marker chip"],
                       linkSpeed: nil),
                   speed: nil,
                   health: PortHealth(plugEvents: 142, connections: 138, overcurrent: 0,
                                      attach: 138, detach: 137, hardResets: 1, roleSwaps: 4),
                   pdOptions: [], pdWinning: nil),
            PortVM(id: 2, portKey: "2/2", title: "Port-USB-C@2", type: "USB-C",
                   summary: PortSummary(
                       status: .thunderboltCable,
                       headline: "Thunderbolt 4 device",
                       subtitle: "External SSD connected at full speed.",
                       bullets: ["Thunderbolt link up (40 Gbps)",
                                 "Cable rated for Thunderbolt / USB4"],
                       linkSpeed: LinkSpeed(tier: .tb40, badge: "40G")),
                   speed: SpeedVM(activeGbps: 40, hostGbps: 40, cableGbps: 40, deviceGbps: 40,
                                  limit: .none, verdict: "Full speed", severity: .good,
                                  summary: "Running at full Thunderbolt speed. Cable is not the limit.",
                                  isWarning: false),
                   health: PortHealth(plugEvents: 61, connections: 60, overcurrent: 0,
                                      attach: 60, detach: 60),
                   pdOptions: [], pdWinning: nil,
                   pins: PinDiagramVM(orientation: 1, activeTransports: ["USB3", "CIO", "DisplayPort", "CC"]),
                   vdo: VDOInfo(kind: "Cable (SOP′)", vendorName: "Anker", vidHex: "0x291A",
                                pidHex: "0x8110", bcdHex: "0x0300", pdRevision: "PD 3.1",
                                certXIDHex: "0x1A2B3C4D", speedLabel: "40 Gbps", currentLabel: "5 A",
                                typeLabel: "passive", maxWatts: 240, eprCapable: true,
                                vdosHex: ["0x18000001", "0x00000000", "0x84008070", "0x00000000"]),
                   events: [PortEventVM(id: 0, label: "Plug", severity: .info),
                            PortEventVM(id: 1, label: "Src caps", severity: .neutral),
                            PortEventVM(id: 2, label: "PD status", severity: .neutral),
                            PortEventVM(id: 3, label: "Identity", severity: .info),
                            PortEventVM(id: 4, label: "Power", severity: .good)]),
            PortVM(id: 3, portKey: "2/3", title: "Port-USB-C@3", type: "USB-C",
                   summary: PortSummary(
                       status: .displayCable,
                       headline: "Display connected",
                       subtitle: "Driving an external monitor over DisplayPort.",
                       bullets: ["DisplayPort Alt Mode active"],
                       linkSpeed: LinkSpeed(tier: .usb10g, badge: "10G")),
                   speed: SpeedVM(activeGbps: 10, hostGbps: 40, cableGbps: 10, deviceGbps: 40,
                                  limit: .cable, verdict: "Cable limits", severity: .warn,
                                  summary: "This cable caps the link at 10 Gbps — the Mac and device both support 40.",
                                  isWarning: true),
                   health: noHealth, pdOptions: [], pdWinning: nil),
            PortVM(id: 4, portKey: "17/1", title: "Port-MagSafe 3@1", type: "MagSafe 3",
                   summary: PortSummary(
                       status: .empty,
                       headline: "Nothing connected",
                       subtitle: "Plug a cable into Port-MagSafe 3@1 to see what it can do.",
                       bullets: [],
                       linkSpeed: nil),
                   speed: nil,
                   health: noHealth, pdOptions: [], pdWinning: nil),
        ]
        // Rising-then-steady power curve filling the whole window.
        m.samples = (0..<powerSampleCap).map { i in
            let w = i < 30 ? Double(i) * 3.0 : 88 + Double((i * 7) % 13)
            return PowerPoint(id: i, watts: w)
        }
        m.power = PowerMonitorSnapshot(
            timestamp: Date(),
            systemSample: PowerSample(timestamp: Date(),
                                      systemVoltageIn: 20_000,
                                      systemCurrentIn: 4_700,
                                      systemPowerIn: 94_000),
            portSamples: [],
            resistanceEstimate: nil,
            externalConnected: true,
            batteryInstalled: true
        )
        m.displays = [
            DisplayVM(id: 0, title: "Studio Display", modeLabel: "5120×2880 @ 60Hz",
                      lanes: 4, maxLanes: 4, deliveredGbps: 25.9, rateDescription: "HBR3",
                      summary: "Running at the monitor's top mode. Cable is not the limit.",
                      isWarning: false),
        ]
        m.adapterWatts = 100
        m.isConnected = true
        m.battery = BatteryVM(soc: 62, isCharging: true, externalConnected: true,
                              fullyCharged: false, minutesToFull: 47, minutesTo80: 18,
                              minutesToEmpty: nil, watts: 94)
        m.resistance = ResistanceVM(milliohms: 128, phase: .stable, sampleCount: 40)
        let t0 = Date(timeIntervalSince1970: 1_710_000_000)
        m.cableStore.seedPreview([
            CableRecord(fingerprint: "a", name: "Desk charger (Anker)", vendorName: "Anker",
                        descriptor: "40 Gbps · 240W · passive", firstSeen: t0, lastSeen: Date(),
                        connectionCount: 214, totalEnergyWh: 18_430, peakWatts: 96,
                        maxSpeedGbps: 40, connectedSeconds: 540_000),
            CableRecord(fingerprint: "b", name: nil, vendorName: "Apple",
                        descriptor: "10 Gbps · 100W", firstSeen: t0, lastSeen: Date(),
                        connectionCount: 58, totalEnergyWh: 4_120, peakWatts: 67,
                        maxSpeedGbps: 10, connectedSeconds: 120_000),
            CableRecord(fingerprint: "c", name: "Travel cable", vendorName: "Belkin",
                        descriptor: "5 Gbps · 60W", firstSeen: t0, lastSeen: Date(),
                        connectionCount: 31, totalEnergyWh: 980, peakWatts: 60,
                        maxSpeedGbps: 5, connectedSeconds: 41_000),
        ])
        m.lastUpdate = Date()
        return m
    }
}
