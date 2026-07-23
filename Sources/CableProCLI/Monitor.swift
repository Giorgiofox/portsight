import Foundation
import WhatCableCore
import WhatCableDarwinBackend

// `cablepro --monitor`: streams live power + battery + cable state to the
// terminal, one line per update (~1 Hz). Log-style (scrolls), unlike the
// full-screen --dashboard.
@MainActor
func runMonitor() async {
    setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: stream lines immediately
    let watcher = PowerTelemetryWatcher()
    watcher.start()

    let ts: () -> String = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    print("cablepro --monitor · Ctrl-C to stop\n")
    for await p in watcher.snapshots {
        let w = Double(p.activePowerMW) / 1000
        let v = Double(p.activeVoltageMV) / 1000
        let a = Double(p.activeCurrentMA) / 1000
        let src = p.onBattery ? "battery" : (p.externalConnected ? "charger" : "—")

        var line = String(format: "%@  %6.2f W  %5.2f V  %5.2f A  %@",
                          ts(), w, v, a, src)

        if let b = AppleSmartBatteryReader.read().battery, b.batteryInstalled {
            let soc = b.maxCapacity > 0
                ? Int((Double(b.currentCapacity) / Double(b.maxCapacity) * 100).rounded())
                : b.currentCapacity
            line += "  · batt \(soc)%"
            if b.isCharging, b.avgTimeToFull > 0, b.avgTimeToFull < 60_000 {
                line += " ▸ full in \(b.avgTimeToFull)m"
            } else if !b.externalConnected, b.avgTimeToEmpty > 0, b.avgTimeToEmpty < 60_000 {
                let h = b.avgTimeToEmpty / 60, m = b.avgTimeToEmpty % 60
                line += " ▸ \(h)h \(m)m left"
            }
        }

        if let r = p.resistanceEstimate, r.status == .stable {
            line += String(format: "  · cable ~%.0f mΩ", r.milliohms)
        }

        print(line)
    }
}
