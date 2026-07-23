# PortSight

**Super-nerdy USB-C diagnostics for Apple Silicon Macs.**

PortSight lives in your menu bar and tells you what every USB-C cable and port
on your Mac is actually doing — negotiated speed, power delivery, health, and
more — plus a full dashboard window with live charts and **per-cable lifetime
statistics** (energy delivered, sessions, peak power, top speed).

Requires macOS 14+ on Apple Silicon.

## Features

**Live diagnostics (menu bar)**
- **Cable speed** — negotiated link speed with the Mac → cable → device chain and
  the limiting element highlighted
- **Power Delivery** — live wattage/voltage/current, PD contract inspector (all
  PDOs decoded, winning profile flagged)
- **Battery** — charge-time estimates (to 80%, to 100%) and remaining runtime
- **Displays** — active resolution/refresh, DisplayPort lanes and link rate
- **Port health** — lifetime attach/detach, link, overcurrent, hard-reset,
  short, I²C, role-swap and FET-failure counters
- **Liquid detection** — LDCM sensor status per port
- **Cable resistance** — milliohm estimate from a multi-point power regression
- **Nerd details** — Type-C pin diagram, raw Discover-Identity VDOs, and a
  decoded PD protocol event trace

**Dashboard window**
- Live system-power chart
- Global stats (total energy delivered, cables tracked)
- Per-cable statistics with energy bar chart, rename and history

**Command line (`portsight` / `cablepro`)**
```
cablepro                 human-readable snapshot
cablepro --json          machine-readable JSON
cablepro --raw           include raw register / VDO dumps
cablepro --watch         live refresh on hardware changes
cablepro --monitor       stream live power + battery + cable state
cablepro --dashboard     full-screen terminal dashboard
```

## Build

```sh
swift build                 # builds cablepro (CLI) + CablePro (app)
./scripts/make-icon.sh      # generate the app icon
./scripts/bundle-app.sh     # → PortSight.app (menu-bar agent)
open PortSight.app
```

Per-cable statistics persist to `~/Library/Application Support/PortSight/`.

## Notes

Cables are identified by their e-marker fingerprint (vendor/product + VDOs).
USB-PD has no per-unit serial, so identical cables of the same model share a
fingerprint. Cables without an e-marker chip (cheap ≤60W / USB 2.0) carry no
identity and cannot be catalogued.

## License

MIT. See `LICENSE` and `NOTICE.md`.
