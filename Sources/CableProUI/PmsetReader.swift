import Foundation

// Reads `pmset -g batt` — macOS's own battery estimate — as an authoritative
// source for time-remaining and charge state, to cross-check/override the raw
// AppleSmartBattery numbers.
struct PmsetInfo: Equatable {
    enum State: String { case charging, discharging, charged, acNotCharging, unknown }
    let percent: Int?
    let state: State
    let minutesRemaining: Int?   // to empty (discharging) or to full (charging); nil if no estimate
}

enum PmsetReader {
    static func read() -> PmsetInfo? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "batt"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        return parse(out)
    }

    static func parse(_ out: String) -> PmsetInfo {
        let lower = out.lowercased()
        let percent = firstMatch(#"(\d+)%"#, in: out).flatMap(Int.init)

        let state: PmsetInfo.State
        if lower.contains("charged") {
            state = .charged
        } else if lower.contains("; charging") || lower.contains(" charging;") {
            state = .charging
        } else if lower.contains("discharging") {
            state = .discharging
        } else if lower.contains("ac ") || lower.contains("'ac power'") || lower.contains("not charging") {
            state = .acNotCharging
        } else {
            state = .unknown
        }

        // Time is formatted "H:MM remaining"; "(no estimate)" / "0:00" mean unknown.
        var minutes: Int?
        if let hm = firstMatch(#"(\d+):(\d\d)\s+remaining"#, in: out, groups: 2) {
            let parts = hm.split(separator: ":")
            if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (h > 0 || m > 0) {
                minutes = h * 60 + m
            }
        }
        return PmsetInfo(percent: percent, state: state, minutesRemaining: minutes)
    }

    // Returns the whole match (groups=0) or "g1:g2" when groups==2.
    private static func firstMatch(_ pattern: String, in text: String, groups: Int = 0) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range) else { return nil }
        if groups == 0 {
            guard let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        } else {
            guard let r1 = Range(m.range(at: 1), in: text),
                  let r2 = Range(m.range(at: 2), in: text) else { return nil }
            return "\(text[r1]):\(text[r2])"
        }
    }
}
