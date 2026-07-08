import Foundation

// MARK: - JSON output
//
// A Codable mirror of the `--json` output. This replaces the previous
// hand-rolled string building: `JSONEncoder` guarantees the output is always
// well-formed and properly escaped (the old version would have produced
// invalid JSON if any label ever contained a quote or backslash), and the
// shape is now described by types rather than string concatenation.
//
// Numeric fields are rounded to two decimals to match the original output and
// to keep the readout tidy when piped through `jq`.

struct JSONReport: Encodable {
    struct Summary: Encodable {
        let thermalState: String
        let hottestC: Double
        let averageC: Double
        let sensorCount: Int
        let fanCount: Int
    }

    struct Temp: Encodable {
        let key: String
        let label: String
        let category: String
        let celsius: Double
    }

    struct Fan: Encodable {
        let fan: Int
        let rpm: Double
        let min: Double
        let max: Double
        let target: Double
        let utilization: Double
    }

    let summary: Summary
    let temperatures: [Temp]
    let fans: [Fan]
}

private func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

/// Builds the structured report from raw readings (kept separate from encoding
/// so it can be unit-tested without going through JSON serialization).
func buildReport(temps: [TempReading], fans: [FanReading]) -> JSONReport {
    let hottest = temps.map { $0.celsius }.max() ?? 0
    let avg = temps.averageCelsius

    return JSONReport(
        summary: .init(
            thermalState: ThermalState.current().name,
            hottestC: round2(hottest),
            averageC: round2(avg),
            sensorCount: temps.count,
            fanCount: fans.count),
        temperatures: temps.map {
            .init(key: $0.key, label: $0.label, category: $0.category.rawValue, celsius: round2($0.celsius))
        },
        fans: fans.map {
            .init(fan: $0.index + 1, rpm: round2($0.rpm), min: round2($0.min),
                  max: round2($0.max), target: round2($0.target), utilization: round2($0.utilization))
        })
}

/// Serializes the report to a compact, deterministic JSON string.
public func renderJSON(temps: [TempReading], fans: [FanReading]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(buildReport(temps: temps, fans: fans)),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}
