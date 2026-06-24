import Foundation

// Lightweight, dependency-free test runner for macthermal's pure logic — no SMC
// hardware or live IOKit connection is required. Build and run with `make test`;
// it prints a summary and exits non-zero if any check fails (CI-friendly).

@main
struct Tests {
    static var checks = 0
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition {
            failures += 1
            FileHandle.standardError.write("  ✗ \(message)\n".data(using: .utf8)!)
        }
    }

    static func eq(_ got: Double?, _ want: Double, _ message: String, eps: Double = 1e-6) {
        expect(got != nil && abs(got! - want) < eps,
               "\(message) — got \(got.map { String($0) } ?? "nil"), want \(want)")
    }

    /// Builds a 32-byte `SMCBytes` tuple from a prefix of bytes (rest zero-filled).
    static func bytes(_ a: [UInt8]) -> SMCBytes {
        var b = a
        while b.count < 32 { b.append(0) }
        return (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15],
                b[16], b[17], b[18], b[19], b[20], b[21], b[22], b[23],
                b[24], b[25], b[26], b[27], b[28], b[29], b[30], b[31])
    }

    static func value(_ type: String, _ b: [UInt8]) -> SMCValue {
        SMCValue(key: "TEST", type: type, size: UInt32(b.count), bytes: bytes(b))
    }

    static func main() {
        // --- SMC value decoding (the fixed-point / float encodings) ---
        eq(value("sp78", [0x3D, 0x00]).double, 61.0, "sp78 0x3D00 = 61.0")
        eq(value("sp78", [0x1E, 0x80]).double, 30.5, "sp78 0x1E80 = 30.5")
        eq(value("flt ", [0x00, 0x00, 0x48, 0x42]).double, 50.0, "flt little-endian = 50.0")
        eq(value("fpe2", [0x00, 0xF0]).double, 60.0, "fpe2 0x00F0 = 60.0 (/4)")
        eq(value("fp88", [0x3D, 0x00]).double, 61.0, "fp88 0x3D00 = 61.0 (/256)")
        eq(value("ui8 ", [0x2A]).double, 42.0, "ui8 = 42")
        eq(value("ui16", [0x01, 0x00]).double, 256.0, "ui16 big-endian = 256")
        eq(value("si8 ", [0xFF]).double, -1.0, "si8 0xFF = -1")
        expect(value("zzzz", [0x00]).double == nil, "unknown type decodes to nil")

        // --- temperature thresholds ---
        expect(tempLevel(59.9).label == "cool" && tempLevel(59.9).severity == .ok, "tempLevel < 60 = cool")
        expect(tempLevel(60).severity == .normal, "tempLevel 60 = normal")
        expect(tempLevel(89).severity == .warn, "tempLevel 89 = warm")
        expect(tempLevel(99).severity == .hot, "tempLevel 99 = hot")
        expect(tempLevel(100).severity == .critical, "tempLevel 100 = critical")

        // --- fan thresholds ---
        expect(fanLevel(4).label == "idle", "fanLevel < 5 = idle")
        expect(fanLevel(49).label == "low", "fanLevel 49 = low")
        expect(fanLevel(50).label == "elevated", "fanLevel 50 = elevated")
        expect(fanLevel(90).label == "maxing", "fanLevel 90 = maxing")

        // --- fan utilization math ---
        eq(FanReading(index: 0, rpm: 2400, min: 1200, max: 6000, target: 0).utilization,
           25.0, "utilization (2400 in 1200..6000) = 25%")
        eq(FanReading(index: 0, rpm: 3000, min: 2000, max: 2000, target: 0).utilization,
           0.0, "utilization with max == min = 0")
        eq(FanReading(index: 0, rpm: 9999, min: 1200, max: 6000, target: 0).utilization,
           100.0, "utilization clamps to 100%")

        // --- categorization (intentionally case-sensitive: SMC naming is) ---
        expect(categorize("Tp00") == .cpu, "Tp00 (P-core) = CPU")
        expect(categorize("TG0P") == .gpu, "TG0P = GPU")
        expect(categorize("TB0T") == .battery, "TB0T = battery")
        expect(categorize("Tm0P") == .memory, "Tm0P = memory")
        expect(categorize("TVD0") == .other, "TVD0 (undocumented SoC rail) = other")

        // --- JSON encoding (round-trips into the expected shape) ---
        let temps = [TempReading(key: "TC0P", label: "CPU proximity", category: .cpu, celsius: 65.789)]
        let fans = [FanReading(index: 0, rpm: 2317.4, min: 1200, max: 5779, target: 2300)]
        let json = renderJSON(temps: temps, fans: fans)
        if let data = json.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let summary = root["summary"] as? [String: Any],
           let temperatures = root["temperatures"] as? [[String: Any]] {
            expect((summary["sensorCount"] as? Int) == 1, "JSON summary.sensorCount = 1")
            expect((summary["fanCount"] as? Int) == 1, "JSON summary.fanCount = 1")
            eq(summary["hottestC"] as? Double, 65.79, "JSON hottestC rounded to 2dp")
            expect((temperatures.first?["key"] as? String) == "TC0P", "JSON temperature key = TC0P")
        } else {
            expect(false, "JSON parses into the expected shape")
        }

        let tag = failures == 0 ? "ok" : "FAILED"
        let summary = "macthermal tests: \(checks - failures)/\(checks) passed — \(tag)\n"
        FileHandle.standardOutput.write(summary.data(using: .utf8)!)
        exit(failures == 0 ? 0 : 1)
    }
}
