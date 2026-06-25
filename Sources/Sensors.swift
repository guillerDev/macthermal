import Foundation

// MARK: - Severity
//
// A UI-agnostic health level. The CLI maps it to ANSI colors; the GUI maps it
// to SwiftUI colors. Neither concern leaks into the sensor layer.

enum Severity {
    case ok, normal, warn, hot, critical
}

// MARK: - Sensor labelling
//
// Friendly names for well-known keys. Unknown keys fall back to a
// prefix-based category so the readout stays meaningful across Mac models.

let knownLabels: [String: String] = [
    "TC0P": "CPU proximity", "TC0D": "CPU die", "TC0E": "CPU", "TC0F": "CPU",
    "TG0P": "GPU proximity", "TG0D": "GPU die",
    "TA0P": "Ambient", "TA1P": "Ambient",
    "Th0H": "Heatsink", "TH0P": "Drive",
    "TB0T": "Battery", "TB1T": "Battery", "TB2T": "Battery",
    "Ts0P": "Skin", "Ts1P": "Skin",
    "Tm0P": "Memory", "TPCD": "PCH",
]

enum Category: String, CaseIterable, Hashable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case battery = "Battery"
    case ambient = "Ambient"
    case other = "Other"
}

func categorize(_ key: String) -> Category {
    let p = key.prefix(2)
    switch p {
    case "Tp", "Te", "TC", "Tc": return .cpu      // performance / efficiency cores, CPU
    case "Tg", "TG": return .gpu
    case "TB": return .battery
    case "TA", "Ts": return .ambient
    case "Tm", "TM": return .memory
    default:
        if knownLabels[key]?.contains("CPU") == true { return .cpu }
        return .other
    }
}

func label(for key: String) -> String { knownLabels[key] ?? key }

// MARK: - Data model

struct TempReading: Equatable { let key: String; let label: String; let category: Category; let celsius: Double }

extension Array where Element == TempReading {
    /// Mean temperature across the readings (0 when empty). Shared so the CLI,
    /// GUI, and JSON report can't drift on how the average is computed.
    var averageCelsius: Double { isEmpty ? 0 : map { $0.celsius }.reduce(0, +) / Double(count) }
}

struct FanReading: Equatable {
    let index: Int
    let rpm: Double
    let min: Double
    let max: Double
    let target: Double
    var utilization: Double { max > min ? Swift.max(0, Swift.min(100, (rpm - min) / (max - min) * 100)) : 0 }
}

// MARK: - Levels (thresholds, shared by CLI + GUI)

func tempLevel(_ c: Double) -> (label: String, severity: Severity) {
    switch c {
    case ..<60:  return ("cool", .ok)
    case ..<78:  return ("normal", .normal)
    case ..<90:  return ("warm", .warn)
    case ..<100: return ("hot", .hot)
    default:     return ("critical", .critical)
    }
}

func fanLevel(_ u: Double) -> (label: String, severity: Severity) {
    switch u {
    case ..<5:  return ("idle", .ok)
    case ..<50: return ("low", .ok)
    case ..<85: return ("elevated", .warn)
    default:    return ("maxing", .hot)
    }
}

// MARK: - OS thermal pressure
//
// The Apple Silicon-supported equivalent of the legacy Intel `pmset -g therm`
// thermal levels (which report "unsupported on this machine" on M-series).

struct ThermalState: Equatable {
    let name: String
    let note: String
    let severity: Severity

    static func current() -> ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return .init(name: "nominal",  note: "no thermal pressure", severity: .ok)
        case .fair:     return .init(name: "fair",     note: "slightly elevated; fans ramping", severity: .normal)
        case .serious:  return .init(name: "serious",  note: "OS is throttling to shed heat", severity: .warn)
        case .critical: return .init(name: "critical", note: "aggressive throttling to prevent shutdown", severity: .critical)
        @unknown default: return .init(name: "unknown", note: "", severity: .ok)
        }
    }
}

// MARK: - Collection

func collectTemps(_ smc: SMC) -> [TempReading] {
    var out: [TempReading] = []
    // `temperatureKeys()` has already filtered to `T…` keys of a temperature
    // type (and caches that set), so here we only read each one's live value
    // and apply a plausibility range to drop spurious readings.
    let keys = (try? smc.temperatureKeys()) ?? []
    for key in keys {
        guard let v = try? smc.read(key), let c = v.double, c > 1, c < 130 else { continue }
        out.append(TempReading(key: key, label: label(for: key), category: categorize(key), celsius: c))
    }
    return out.sorted { $0.celsius > $1.celsius }
}

func collectFans(_ smc: SMC) -> [FanReading] {
    guard let countVal = try? smc.read("FNum"), let count = countVal.double else { return [] }
    var fans: [FanReading] = []
    for i in 0..<Int(count) {
        let rpm = (try? smc.read("F\(i)Ac"))?.double ?? 0
        let mn = (try? smc.read("F\(i)Mn"))?.double ?? 0
        let mx = (try? smc.read("F\(i)Mx"))?.double ?? 0
        let tg = (try? smc.read("F\(i)Tg"))?.double ?? 0
        fans.append(FanReading(index: i, rpm: rpm, min: mn, max: mx, target: tg))
    }
    return fans
}

// MARK: - Snapshot (aggregate convenience for UIs)

struct Snapshot {
    let temps: [TempReading]
    let fans: [FanReading]
    let thermal: ThermalState

    var hottest: TempReading? { temps.first }   // collectTemps returns hottest-first
    var averageC: Double { temps.averageCelsius }
    func group(_ c: Category) -> [TempReading] { temps.filter { $0.category == c } }

    static func capture(_ smc: SMC) -> Snapshot {
        Snapshot(temps: collectTemps(smc), fans: collectFans(smc), thermal: .current())
    }
}
