import Foundation
import WhatCableCore
import WhatCableDarwinBackend

// CablePro CLI — one-shot or live USB-C cable diagnostics.
//
// Usage:
//   cablepro                 human-readable snapshot (once)
//   cablepro --json          machine-readable JSON snapshot
//   cablepro --raw           include raw register / VDO dumps
//   cablepro --watch         live-refresh on hardware changes
//   cablepro --help

struct Options {
    var json = false
    var raw = false
    var watch = false
    var dashboard = false
    var monitor = false
}

func parseOptions(_ argv: [String]) -> Options {
    var o = Options()
    for arg in argv {
        switch arg {
        case "--json", "-j": o.json = true
        case "--raw", "-r": o.raw = true
        case "--watch", "-w": o.watch = true
        case "--dashboard", "-d": o.dashboard = true
        case "--monitor", "-m": o.monitor = true
        default: break
        }
    }
    return o
}

func printUsage() {
    print("""
    cablepro — USB-C cable diagnostics (Apple Silicon, macOS 14+)

    Usage:
      cablepro [options]

    Options:
      -j, --json    Emit JSON instead of text
      -r, --raw     Include raw register / VDO dumps
      -w, --watch      Live-refresh on hardware changes (Ctrl-C to stop)
      -d, --dashboard  Full-screen TUI with live power monitor (Ctrl-C to stop)
      -m, --monitor    Stream live power + battery + cable state, one line/sec
      -h, --help       Show this help
    """)
}

func render(_ snapshot: CableSnapshot, options: Options) throws {
    if options.json {
        let json = try JSONFormatter.render(
            ports: snapshot.ports,
            sources: snapshot.powerSources,
            identities: snapshot.identities,
            showRaw: options.raw,
            adapter: snapshot.adapter,
            thunderboltSwitches: snapshot.thunderboltSwitches,
            isDesktopMac: snapshot.isDesktopMac,
            batteryFullyCharged: snapshot.batteryFullyCharged,
            batteryIsCharging: snapshot.batteryIsCharging,
            federatedIdentities: snapshot.federatedIdentities,
            usb3Transports: snapshot.usb3Transports,
            trmTransports: snapshot.trmTransports,
            cioCapabilities: snapshot.cioCapabilities,
            usbDevices: snapshot.usbDevices,
            displayPorts: snapshot.displayPorts,
            builtInDisplayPorts: BuiltInDisplayPort.group(from: snapshot.displayPorts)
        )
        print(json)
    } else {
        let text = TextFormatter.render(
            ports: snapshot.ports,
            sources: snapshot.powerSources,
            identities: snapshot.identities,
            showRaw: options.raw,
            adapter: snapshot.adapter,
            thunderboltSwitches: snapshot.thunderboltSwitches,
            isDesktopMac: snapshot.isDesktopMac,
            batteryFullyCharged: snapshot.batteryFullyCharged,
            batteryIsCharging: snapshot.batteryIsCharging,
            federatedIdentities: snapshot.federatedIdentities,
            usb3Transports: snapshot.usb3Transports,
            cioCapabilities: snapshot.cioCapabilities,
            usbDevices: snapshot.usbDevices,
            displayPorts: snapshot.displayPorts,
            builtInDisplayPorts: BuiltInDisplayPort.group(from: snapshot.displayPorts)
        )
        print(text, terminator: "")
    }
}

// ── Entry point ────────────────────────────────────────────────────────
let argv = Array(CommandLine.arguments.dropFirst())
if argv.contains("--help") || argv.contains("-h") {
    printUsage()
    exit(0)
}

let options = parseOptions(argv)

if options.dashboard {
    await Dashboard().run()
    exit(0)
}

if options.monitor {
    await runMonitor()
    exit(0)
}

if argv.contains("--debug-power") {
    await runDebugPower()
    exit(0)
}

let provider = makeDefaultSnapshotProvider()

if options.watch {
    do {
        for try await snapshot in provider.watch() {
            print("\u{1B}[2J\u{1B}[H", terminator: "")  // clear + home
            print("cablepro --watch · \(Date())\n")
            try render(snapshot, options: options)
        }
    } catch {
        FileHandle.standardError.write(Data("cablepro: \(error)\n".utf8))
        exit(1)
    }
} else {
    do {
        let snapshot = try await provider.snapshot()
        try render(snapshot, options: options)
    } catch {
        FileHandle.standardError.write(Data("cablepro: \(error)\n".utf8))
        exit(1)
    }
}
