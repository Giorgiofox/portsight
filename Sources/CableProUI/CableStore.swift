import Foundation
import WhatCableCore

// Persistent per-cable statistics (feature #1 Cable History + energy stats).
// Each e-markered cable is identified by a fingerprint derived from its
// Discover Identity VDOs. NOTE: USB-PD has no per-unit serial, so two identical
// cables of the same model share a fingerprint — this is model-level identity.

public struct CableRecord: Codable, Identifiable, Equatable {
    public var id: String { fingerprint }
    public let fingerprint: String
    public var name: String?              // user-assigned nickname
    public var vendorName: String
    public var descriptor: String         // "40 Gbps · 240W · passive"
    public var firstSeen: Date
    public var lastSeen: Date
    public var connectionCount: Int
    public var totalEnergyWh: Double       // lifetime energy delivered
    public var peakWatts: Double
    public var maxSpeedGbps: Double
    public var connectedSeconds: Double    // lifetime time connected

    public var displayName: String { name ?? vendorName }
    public var totalEnergyKWh: Double { totalEnergyWh / 1000 }
}

// Persistent per-charger statistics. Identified from AdapterDetails. Genuine
// Apple/PD bricks may report a serial (per-unit); many third-party ones only
// report watts + family/PMU/PDO, so this is model/type-level identity.
public struct ChargerRecord: Codable, Identifiable, Equatable {
    public var id: String { fingerprint }
    public let fingerprint: String
    public var name: String?              // user-assigned nickname
    public var label: String              // "Apple 96W USB-C" / "90W charger"
    public var descriptor: String         // "90W · 20V/4.5A"
    public var firstSeen: Date
    public var lastSeen: Date
    public var sessionCount: Int
    public var totalEnergyWh: Double
    public var peakWatts: Double
    public var connectedSeconds: Double

    public var displayName: String { name ?? label }
    public var totalEnergyKWh: Double { totalEnergyWh / 1000 }
}

@MainActor
public final class CableStore: ObservableObject {
    @Published public private(set) var records: [String: CableRecord] = [:]
    @Published public private(set) var chargers: [String: ChargerRecord] = [:]

    private let url: URL
    private let inMemory: Bool
    private var saveScheduled = false

    /// `inMemory` skips disk load/save — used for offscreen previews so real
    /// catalogued cables never leak into rendered screenshots.
    public init(inMemory: Bool = false) {
        self.inMemory = inMemory
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortSight", isDirectory: true)
        if !inMemory {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        url = base.appendingPathComponent("cables.json")
        if !inMemory { load() }
    }

    public var all: [CableRecord] {
        records.values.sorted { $0.totalEnergyWh > $1.totalEnergyWh }
    }

    public var totalEnergyKWh: Double {
        records.values.reduce(0) { $0 + $1.totalEnergyWh } / 1000
    }

    public var allChargers: [ChargerRecord] {
        chargers.values.sorted { $0.totalEnergyWh > $1.totalEnergyWh }
    }

    /// Register/refresh a charger seen now.
    public func observeCharger(fingerprint: String, label: String, descriptor: String, now: Date) {
        if var rec = chargers[fingerprint] {
            let isReconnect = now.timeIntervalSince(rec.lastSeen) > 60
            rec.lastSeen = now
            if !descriptor.isEmpty { rec.descriptor = descriptor }
            // Enrich the auto label once the PD brand arrives (a moment after the
            // bare AdapterDetails one). Prefer the longer/branded label.
            if label.count > rec.label.count { rec.label = label }
            if isReconnect { rec.sessionCount += 1 }
            chargers[fingerprint] = rec
            scheduleSave()
        } else {
            chargers[fingerprint] = ChargerRecord(
                fingerprint: fingerprint, name: nil, label: label, descriptor: descriptor,
                firstSeen: now, lastSeen: now, sessionCount: 1,
                totalEnergyWh: 0, peakWatts: 0, connectedSeconds: 0)
            scheduleSave()
        }
    }

    public func accumulateCharger(fingerprint: String, watts: Double, seconds: Double, now: Date) {
        guard var rec = chargers[fingerprint] else { return }
        rec.totalEnergyWh += watts * (seconds / 3600)
        rec.connectedSeconds += seconds
        rec.peakWatts = max(rec.peakWatts, watts)
        rec.lastSeen = now
        chargers[fingerprint] = rec
        scheduleSave()
    }

    public func renameCharger(_ fingerprint: String, to name: String?) {
        guard var rec = chargers[fingerprint] else { return }
        rec.name = (name?.isEmpty ?? true) ? nil : name
        chargers[fingerprint] = rec
        save()
    }

    public func forgetCharger(_ fingerprint: String) {
        chargers[fingerprint] = nil
        save()
    }

    public func seedPreviewChargers(_ recs: [ChargerRecord]) {
        for r in recs { chargers[r.fingerprint] = r }
    }

    /// Register/refresh a cable seen now. Returns true if it's a new connection
    /// (fingerprint not seen in the last session) for connection counting.
    @discardableResult
    public func observe(fingerprint: String, vendorName: String, descriptor: String,
                        speedGbps: Double, now: Date) -> Bool {
        if var rec = records[fingerprint] {
            let isReconnect = now.timeIntervalSince(rec.lastSeen) > 60
            rec.lastSeen = now
            rec.maxSpeedGbps = max(rec.maxSpeedGbps, speedGbps)
            if !descriptor.isEmpty { rec.descriptor = descriptor }
            if isReconnect { rec.connectionCount += 1 }
            records[fingerprint] = rec
            scheduleSave()
            return isReconnect
        } else {
            records[fingerprint] = CableRecord(
                fingerprint: fingerprint, name: nil, vendorName: vendorName,
                descriptor: descriptor, firstSeen: now, lastSeen: now,
                connectionCount: 1, totalEnergyWh: 0, peakWatts: 0,
                maxSpeedGbps: speedGbps, connectedSeconds: 0)
            scheduleSave()
            return true
        }
    }

    /// Accumulate a slice of delivered energy + connected time onto a cable.
    public func accumulate(fingerprint: String, watts: Double, seconds: Double, now: Date) {
        guard var rec = records[fingerprint] else { return }
        rec.totalEnergyWh += watts * (seconds / 3600)
        rec.connectedSeconds += seconds
        rec.peakWatts = max(rec.peakWatts, watts)
        rec.lastSeen = now
        records[fingerprint] = rec
        scheduleSave()
    }

    public func rename(_ fingerprint: String, to name: String?) {
        guard var rec = records[fingerprint] else { return }
        rec.name = (name?.isEmpty ?? true) ? nil : name
        records[fingerprint] = rec
        save()
    }

    public func forget(_ fingerprint: String) {
        records[fingerprint] = nil
        save()
    }

    /// Seed records for offscreen previews (does not touch disk).
    public func seedPreview(_ recs: [CableRecord]) {
        for r in recs { records[r.fingerprint] = r }
    }

    // MARK: persistence

    private struct Persisted: Codable {
        var cables: [String: CableRecord]
        var chargers: [String: ChargerRecord]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            records = p.cables
            // Drop charger records saved under an old, unstable key scheme so the
            // catalog self-heals to one entry per charger (keyed by VID+PID).
            chargers = p.chargers.filter { $0.key.range(of: ChargerIdentity.keyRegex,
                                                        options: .regularExpression) != nil }
        } else if let old = try? JSONDecoder().decode([String: CableRecord].self, from: data) {
            records = old   // migrate pre-charger format
        }
    }

    /// Debounced save (energy accumulates every second; don't hit disk each tick).
    private func scheduleSave() {
        guard !inMemory, !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.saveScheduled = false
            self?.save()
        }
    }

    private func save() {
        guard !inMemory else { return }
        let payload = Persisted(cables: records, chargers: chargers)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Fingerprint derivation

public enum CableIdentity {
    /// Build a stable fingerprint key + descriptor + rated speed from a cable
    /// e-marker identity. `ratedGbps` is the cable's own capability (from its
    /// e-marker), independent of the link currently negotiated on the port.
    public static func make(from identity: USBPDSOP)
        -> (key: String, vendor: String, descriptor: String, ratedGbps: Double)? {
        let fp = CableReport.CableFingerprint(identity: identity)
        guard fp.hasEmarker else { return nil }
        let vdoKey = fp.vdos.map { String($0, radix: 16) }.joined(separator: ".")
        let key = "\(fp.vendorIDHex)-\(fp.productIDHex)-\(vdoKey)"
        var parts: [String] = []
        if let s = fp.speed { parts.append(s) }
        if let w = fp.maxWatts { parts.append("\(w)W") }
        if let t = fp.type { parts.append(t) }
        return (key, fp.vendorName, parts.joined(separator: " · "), gbps(from: fp.speed))
    }

    /// Parse a Gbps figure from an e-marker speed label like
    /// "USB 3.2 Gen 1 (5 Gbps)" / "40 Gbps" / "USB 2.0 (480 Mbps)".
    static func gbps(from label: String?) -> Double {
        guard let s = label else { return 0 }
        func firstNumber(before unit: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*" + unit) else { return nil }
            let range = NSRange(s.startIndex..., in: s)
            guard let m = re.firstMatch(in: s, range: range),
                  let r = Range(m.range(at: 1), in: s) else { return nil }
            return Double(s[r])
        }
        if let g = firstNumber(before: "Gbps") { return g }
        if let mbps = firstNumber(before: "Mbps") { return mbps / 1000 }
        return 0
    }
}

public enum ChargerIdentity {
    /// Fingerprint a charger. Brand/serial come from the charger's USB-PD
    /// Discover Identity (`partner`, the SOP port-partner): its VID maps to a
    /// manufacturer via the USB-IF DB, and the Cert-Stat XID acts as a
    /// (model-level) ID. Watts/PD profile come from `adapter` (AdapterDetails).
    /// Canonical charger key: "chg-<vid>-<pid>" (lowercase hex). Stable across
    /// reconnects and across watt renegotiations of the same charger.
    static let keyRegex = "^chg-[0-9a-f]{4}-[0-9a-f]{4}$"

    public static func make(adapter: AdapterInfo?, partner: USBPDSOP?)
        -> (key: String, label: String, descriptor: String)? {
        // Require the PD Discover Identity: its VID+PID is the only stable key.
        // (AdapterDetails watts fluctuate — e.g. a monitor negotiating 60↔90W —
        // so keying on them spawns duplicates.) Chargers that don't advertise a
        // PD identity aren't catalogued.
        guard let p = partner else { return nil }

        let brand = CableDB.vendorName(vid: p.vendorID) ?? adapter?.manufacturer ?? adapter?.name
        let vidHex = String(format: "0x%04X", p.vendorID)
        let xidHex: String? = (p.certStatVDO.flatMap { $0.isPresent ? String(format: "0x%08X", $0.xid) : nil })

        // Rated (max) watts from the charger's PD/HVC profile menu, so the label
        // stays put instead of flipping with the momentary negotiated contract.
        let maxW: Int? = {
            let hvcMax = adapter?.hvcMenu.map(\.wattsInt).max() ?? 0
            let w = max(hvcMax, adapter?.watts ?? 0)
            return w > 0 ? w : nil
        }()

        let key = String(format: "chg-%04x-%04x", p.vendorID, p.productID)
        let label = [brand, maxW.map { "\($0)W" }].compactMap { $0 }.joined(separator: " ")
        let finalLabel = label.isEmpty ? "USB-C charger" : label

        var parts: [String] = []
        if let w = maxW { parts.append("\(w)W") }
        if let v = adapter?.voltageMV, let c = adapter?.currentMA, v > 0, c > 0 {
            parts.append(String(format: "%.0fV/%.1fA", Double(v) / 1000, Double(c) / 1000))
        }
        parts.append("VID \(vidHex)")
        if let x = xidHex { parts.append("ID \(x)") }
        return (key, finalLabel, parts.joined(separator: " · "))
    }
}
