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

@MainActor
public final class CableStore: ObservableObject {
    @Published public private(set) var records: [String: CableRecord] = [:]

    private let url: URL
    private var saveScheduled = false

    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortSight", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("cables.json")
        load()
    }

    public var all: [CableRecord] {
        records.values.sorted { $0.totalEnergyWh > $1.totalEnergyWh }
    }

    public var totalEnergyKWh: Double {
        records.values.reduce(0) { $0 + $1.totalEnergyWh } / 1000
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

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CableRecord].self, from: data)
        else { return }
        records = decoded
    }

    /// Debounced save (energy accumulates every second; don't hit disk each tick).
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.saveScheduled = false
            self?.save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Fingerprint derivation

public enum CableIdentity {
    /// Build a stable fingerprint key + descriptor from a cable e-marker identity.
    public static func make(from identity: USBPDSOP) -> (key: String, vendor: String, descriptor: String)? {
        let fp = CableReport.CableFingerprint(identity: identity)
        guard fp.hasEmarker else { return nil }
        let vdoKey = fp.vdos.map { String($0, radix: 16) }.joined(separator: ".")
        let key = "\(fp.vendorIDHex)-\(fp.productIDHex)-\(vdoKey)"
        var parts: [String] = []
        if let s = fp.speed { parts.append(s) }
        if let w = fp.maxWatts { parts.append("\(w)W") }
        if let t = fp.type { parts.append(t) }
        return (key, fp.vendorName, parts.joined(separator: " · "))
    }
}
