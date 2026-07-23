import Foundation
import Darwin
import WhatCableCore
import WhatCableDarwinBackend

// Full-screen terminal dashboard: `cablepro --dashboard`.
//
// Combines the live cable snapshot (per-port diagnostics) with a live
// System Power Monitor — a sparkline of power input over time (feature C),
// driven by PowerTelemetryWatcher's 1 Hz stream.

// MARK: - Terminal control

enum Term {
    static let esc = "\u{1B}["
    static func write(_ s: String) { FileHandle.standardOutput.write(Data(s.utf8)) }

    static func enterFullScreen() {
        write(esc + "?1049h")   // alternate screen buffer
        write(esc + "?25l")     // hide cursor
        write(esc + "2J")       // clear
    }
    static func leaveFullScreen() {
        write(esc + "?25h")     // show cursor
        write(esc + "?1049l")   // restore primary screen
    }
    static func home() { write(esc + "H") }
    static func clearToEOL() -> String { esc + "K" }
    static func clearBelow() -> String { esc + "J" }

    static func size() -> (rows: Int, cols: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0, w.ws_row > 0 {
            return (Int(w.ws_row), Int(w.ws_col))
        }
        return (40, 100)  // sane fallback
    }
}

// MARK: - ANSI helpers (colors)

enum C {
    static let reset = "\u{1B}[0m"
    static let bold = "\u{1B}[1m"
    static let dim = "\u{1B}[2m"
    static let cyan = "\u{1B}[36m"
    static let green = "\u{1B}[32m"
    static let yellow = "\u{1B}[33m"
    static let red = "\u{1B}[31m"
    static func wrap(_ codes: String, _ s: String) -> String { codes + s + reset }
}

// MARK: - Dashboard state + render

@MainActor
final class Dashboard {
    private var cable: CableSnapshot?
    private var power: PowerMonitorSnapshot?
    private var history: [Int] = []          // recent activePowerMW samples (ring)
    private let historyCap = 240             // ~4 min at 1 Hz; trimmed to width
    private let started = Date()

    private let provider = makeDefaultSnapshotProvider()
    private let powerWatcher = PowerTelemetryWatcher()

    private static let bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    func run() async {
        installSignalHandlers()
        Term.enterFullScreen()
        powerWatcher.start()

        // Feed cable snapshots (also hands ports to the power watcher for
        // per-port UUID mapping on M3+).
        let cableTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.provider.watch()
            for try await snap in stream {
                self.cable = snap
                self.powerWatcher.updatePorts(snap.ports)
                self.render()
            }
        }

        // Power stream is the render clock (~1 Hz).
        for await snap in powerWatcher.snapshots {
            power = snap
            history.append(snap.activePowerMW)
            if history.count > historyCap { history.removeFirst(history.count - historyCap) }
            render()
        }
        cableTask.cancel()
    }

    // MARK: signals

    private func installSignalHandlers() {
        let restore: @convention(c) (Int32) -> Void = { _ in
            Term.leaveFullScreen()
            exit(0)
        }
        signal(SIGINT, restore)
        signal(SIGTERM, restore)
    }

    // MARK: rendering

    private func render() {
        let (rows, cols) = Term.size()
        var lines: [String] = []

        lines.append(header(cols: cols))
        lines.append(rule(cols))
        lines.append(contentsOf: powerSection(cols: cols))
        lines.append(rule(cols))
        lines.append(C.wrap(C.bold, "PORTS"))
        lines.append(contentsOf: portsSection())

        // Clip to terminal height, then paint with minimal flicker.
        let clipped = Array(lines.prefix(max(1, rows - 1)))
        var frame = ""
        Term.home()
        for line in clipped {
            frame += line + Term.clearToEOL() + "\r\n"
        }
        frame += Term.clearBelow()
        Term.write(frame)
    }

    private func rule(_ cols: Int) -> String {
        C.wrap(C.dim, String(repeating: "─", count: max(0, min(cols, 120))))
    }

    private func header(cols: Int) -> String {
        let elapsed = Int(-started.timeIntervalSinceNow)
        let left = C.wrap(C.bold + C.cyan, "CablePro Dashboard")
            + C.wrap(C.dim, "  ·  \(elapsed)s  ·  1 Hz")
        let right = C.wrap(C.dim, "q / Ctrl-C to quit")
        return pad(left, right, cols: min(cols, 120))
    }

    // Feature C: System Power Monitor
    private func powerSection(cols: Int) -> [String] {
        guard let p = power else {
            return [C.wrap(C.dim, "  reading power telemetry…")]
        }
        let watts = Double(p.activePowerMW) / 1000.0
        let volts = Double(p.activeVoltageMV) / 1000.0
        let amps = Double(p.activeCurrentMA) / 1000.0

        let source: String
        if p.onBattery {
            source = C.wrap(C.yellow, "🔋 on battery")
        } else if p.externalConnected {
            source = C.wrap(C.green, "⚡ charger")
        } else {
            source = C.wrap(C.dim, "—")
        }

        let title = C.wrap(C.bold, "SYSTEM POWER \(p.onBattery ? "OUT" : "IN")")
        let readout = String(
            format: "  %@%.1f W%@   (%.2f V · %.2f A)   %@",
            C.bold, watts, C.reset, volts, amps, source
        )

        // Peak label used to scale the sparkline (charger rating if higher).
        let observedPeakMW = history.max() ?? p.activePowerMW
        let adapterMW = (cable?.adapter?.watts ?? 0) * 1000
        let scaleMW = max(observedPeakMW, adapterMW, 1)

        let width = max(10, min(cols - 6, 100))
        let spark = sparkline(history, width: width, scaleMW: scaleMW)
        let peakLabel = C.wrap(C.dim, "peak \(Int((Double(observedPeakMW)/1000).rounded())) W · scale \(Int((Double(scaleMW)/1000).rounded())) W")

        var out = [title, readout, "  " + spark + "  " + peakLabel]

        // Cable resistance estimate (part of feature C's port health).
        if let r = p.resistanceEstimate {
            let mo = String(format: "%.0f", r.milliohms)
            let statusColor: String
            switch r.status {
            case .stable: statusColor = C.green
            case .insufficient: statusColor = C.dim
            case .converging: statusColor = C.yellow
            case .unreliable: statusColor = C.red
            }
            out.append("  " + C.wrap(C.dim, "cable resistance: ")
                + C.wrap(statusColor, "~\(mo) mΩ (\(r.status.rawValue))"))
        }
        return out
    }

    private func sparkline(_ samples: [Int], width: Int, scaleMW: Int) -> String {
        guard !samples.isEmpty else { return C.wrap(C.dim, String(repeating: "·", count: width)) }
        let tail = Array(samples.suffix(width))
        let leadPad = width - tail.count
        var s = String(repeating: " ", count: max(0, leadPad))
        for v in tail {
            let frac = Double(max(0, v)) / Double(scaleMW)
            let idx = min(Self.bars.count - 1, max(0, Int(frac * Double(Self.bars.count - 1))))
            let bar = Self.bars[idx]
            let color = frac > 0.85 ? C.red : (frac > 0.5 ? C.yellow : C.green)
            s += C.wrap(color, bar)
        }
        return s
    }

    private func portsSection() -> [String] {
        guard let snap = cable else { return [C.wrap(C.dim, "  reading ports…")] }
        let text = TextFormatter.render(
            ports: snap.ports,
            sources: snap.powerSources,
            identities: snap.identities,
            showRaw: false,
            adapter: snap.adapter,
            thunderboltSwitches: snap.thunderboltSwitches,
            isDesktopMac: snap.isDesktopMac,
            batteryFullyCharged: snap.batteryFullyCharged,
            batteryIsCharging: snap.batteryIsCharging,
            federatedIdentities: snap.federatedIdentities,
            usb3Transports: snap.usb3Transports,
            cioCapabilities: snap.cioCapabilities,
            usbDevices: snap.usbDevices,
            displayPorts: snap.displayPorts,
            builtInDisplayPorts: BuiltInDisplayPort.group(from: snap.displayPorts)
        )
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
    }

    // Pads `left` … `right` to `cols`, ignoring ANSI width (approx: strip codes).
    private func pad(_ left: String, _ right: String, cols: Int) -> String {
        let lw = visibleWidth(left), rw = visibleWidth(right)
        let gap = max(1, cols - lw - rw)
        return left + String(repeating: " ", count: gap) + right
    }

    private func visibleWidth(_ s: String) -> Int {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression).count
    }
}
