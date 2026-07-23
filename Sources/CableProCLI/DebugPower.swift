import Foundation
import WhatCableCore
import WhatCableDarwinBackend

// `cablepro --debug-power`: dumps the raw per-port power telemetry the cable
// resistance regression depends on, so we can see whether the voltage-drop
// data is present and whether the current is varying enough to converge.
@MainActor
func runDebugPower() async {
    setvbuf(stdout, nil, _IONBF, 0)
    let watcher = PowerTelemetryWatcher()
    watcher.start()
    print("cablepro --debug-power · Ctrl-C to stop\n")
    print("Resistance needs: >=30 samples, current swing >200mA, voltage drop present.\n")
    for await p in watcher.snapshots {
        let r = p.resistanceEstimate
        print("── tick · resistance: \(r?.status.rawValue ?? "nil") "
              + "samples=\(r?.sampleCount ?? 0) "
              + "r²=\(String(format: "%.2f", r?.rSquared ?? 0)) "
              + "mΩ=\(String(format: "%.0f", r?.milliohms ?? 0))")
        print("   system: \(Double(p.activePowerMW)/1000) W  externalConnected=\(p.externalConnected) onBattery=\(p.onBattery) perPortMetering=\(p.perPortMeteringSupported)")
        if p.portSamples.isEmpty {
            print("   portSamples: NONE (no per-port telemetry on this Mac)")
        }
        for s in p.portSamples {
            let drop = s.configuredVoltage - s.adapterVoltage
            print("   port \(s.portKey): current=\(s.current)mA configuredV=\(s.configuredVoltage)mV adapterV=\(s.adapterVoltage)mV drop=\(drop)mV watts=\(s.watts)")
        }
    }
}
