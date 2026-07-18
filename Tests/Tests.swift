import Foundation
// Under SwiftPM/Xcode the core is a separate module; the flat `swiftc` test
// build compiles core + tests as one module, where this import doesn't resolve
// (and `canImport` is false, so the guard removes it).
#if canImport(MacThermalCore)
import MacThermalCore
#endif

// Lightweight, dependency-free test runner for macthermal's pure logic — no SMC
// hardware or live IOKit connection is required. Build and run with `make test`;
// it prints a summary and exits non-zero if any check fails (CI-friendly).

@main
@MainActor
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

    static func sample(
        seconds: TimeInterval,
        hotspot: Double,
        fan: Double = 20,
        severity: Severity = .ok,
        processCPU: Double = 0,
        processSnapshotID: UUID? = nil
    ) -> ThermalSample {
        let processes = processCPU > 0
            ? [ProcessUsage(pid: 42, name: "RenderApp", cpuPercent: processCPU)]
            : []
        let stateName: String
        switch severity {
        case .warn: stateName = "serious"
        case .critical: stateName = "critical"
        default: stateName = "nominal"
        }
        return ThermalSample(
            timestamp: Date(timeIntervalSince1970: seconds),
            hottestCelsius: hotspot,
            averageCelsius: hotspot - 10,
            categoryPeaks: ["CPU": hotspot],
            fanRPM: [2_000],
            fanUtilization: [fan],
            thermalStateName: stateName,
            thermalSeverity: severity,
            topProcesses: processes,
            processSnapshotID: processSnapshotID,
            processSampledAt: processSnapshotID.map { _ in Date(timeIntervalSince1970: seconds) }
        )
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

        // --- size guards: a too-short value decodes to nil, not garbage ---
        expect(value("flt ", [0x00, 0x00, 0x48]).double == nil, "flt with 3 bytes = nil")
        expect(value("ui16", [0x01]).double == nil, "ui16 with 1 byte = nil")
        expect(value("ui32", [0x01, 0x02, 0x03]).double == nil, "ui32 with 3 bytes = nil")
        expect(value("sp78", [0x3D]).double == nil, "sp78 with 1 byte = nil")

        // --- count clamping (SEC-1): untrusted SMC counts can't crash/blow up ---
        expect(clampedCount(.nan, upperBound: 8192) == 0, "clampedCount(NaN) = 0")
        expect(clampedCount(.infinity, upperBound: 8192) == 0, "clampedCount(∞) = 0")
        expect(clampedCount(-5, upperBound: 8192) == 0, "clampedCount(negative) = 0")
        expect(clampedCount(3, upperBound: 8192) == 3, "clampedCount(3) = 3")
        expect(clampedCount(1e12, upperBound: 8192) == 8192, "clampedCount(huge) = upperBound")
        expect(clampedCount(1e300, upperBound: 8192) == 8192, "clampedCount(> Int.max) = upperBound (no trap)")

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

        // --- Pro history summaries and before/after comparison ---
        let baselineSamples = [
            sample(seconds: 0, hotspot: 60, fan: 10),
            sample(seconds: 10, hotspot: 70, fan: 20),
        ]
        let currentSamples = [
            sample(seconds: 20, hotspot: 75, fan: 30),
            sample(seconds: 30, hotspot: 85, fan: 40, severity: .warn),
        ]
        let baselineSummary = ThermalSummary(samples: baselineSamples)
        eq(baselineSummary.averageHotspotCelsius, 65, "history average hotspot = 65°C")
        eq(baselineSummary.averageFanUtilization, 15, "history average fan utilization = 15%")
        let comparison = ThermalComparison(baselineSamples: baselineSamples, currentSamples: currentSamples)
        eq(comparison.hotspotDeltaCelsius, 15, "comparison hotspot delta = +15°C")
        expect(comparison.current.pressureSampleCount == 1, "comparison counts serious pressure samples")

        // --- chart density reduction preserves chronology and thermal peaks ---
        let denseSamples = (0..<2_500).map { index in
            sample(
                seconds: TimeInterval(index),
                hotspot: index == 1_234 ? 112 : 60 + Double(index % 8)
            )
        }
        let reducedSamples = ThermalSampleDownsampler.samples(from: denseSamples, maximumCount: 100)
        expect(reducedSamples.count <= 100, "chart downsampling honors its maximum count")
        expect(reducedSamples.first?.id == denseSamples.first?.id, "chart downsampling preserves the first sample")
        expect(reducedSamples.last?.id == denseSamples.last?.id, "chart downsampling preserves the last sample")
        expect(reducedSamples.contains { $0.hottestCelsius == 112 }, "chart downsampling preserves a hotspot spike")
        expect(zip(reducedSamples, reducedSamples.dropFirst()).allSatisfy { pair in
            pair.0.timestamp < pair.1.timestamp
        },
               "chart downsampling preserves chronological order")
        let threeSamples = ThermalSampleDownsampler.samples(from: denseSamples, maximumCount: 3)
        expect(threeSamples.count == 3 && threeSamples[1].hottestCelsius == 112,
               "three-point downsampling keeps the hottest interior sample")

        // --- process/heat correlation ---
        let correlationSamples = [
            sample(seconds: 0, hotspot: 50, processCPU: 10),
            sample(seconds: 10, hotspot: 60, processCPU: 20),
            sample(seconds: 20, hotspot: 70, processCPU: 30),
            sample(seconds: 30, hotspot: 80, processCPU: 40),
        ]
        let correlations = ThermalAnalytics.processCorrelations(samples: correlationSamples)
        expect(correlations.first?.processName == "RenderApp", "correlation identifies sampled process")
        eq(correlations.first?.coefficient, 1, "perfect process/temperature correlation = 1")

        let sparseCorrelationSamples = [
            sample(seconds: 0, hotspot: 50, processCPU: 10),
            sample(seconds: 10, hotspot: 60),
            sample(seconds: 20, hotspot: 70, processCPU: 30),
            sample(seconds: 30, hotspot: 80, processCPU: 40),
        ]
        let sparseCorrelations = ThermalAnalytics.processCorrelations(samples: sparseCorrelationSamples)
        expect(sparseCorrelations.first?.samplesObserved == 3, "correlation counts only samples where a process appears")
        eq(sparseCorrelations.first?.averageCPUPercent, 20, "correlation treats an absent process as 0% CPU")

        let processCaptureIDs = [UUID(), UUID(), UUID()]
        var repeatedProcessSamples: [ThermalSample] = []
        for (capture, id) in processCaptureIDs.enumerated() {
            for duplicate in 0..<3 {
                repeatedProcessSamples.append(sample(
                    seconds: TimeInterval(capture * 15 + duplicate * 2),
                    hotspot: 50 + Double(capture * 10 + duplicate),
                    processCPU: 10 + Double(capture * 10),
                    processSnapshotID: id
                ))
            }
        }
        let deduplicatedCorrelations = ThermalAnalytics.processCorrelations(samples: repeatedProcessSamples)
        expect(deduplicatedCorrelations.first?.samplesObserved == 3,
               "correlation counts one observation per real process capture")

        // --- comparison coverage rejects sparse or incomplete periods ---
        let completeCoverageSamples = stride(from: 0, through: 3_600, by: 30).map {
            sample(seconds: TimeInterval($0), hotspot: 65)
        }
        let completeCoverage = ThermalPeriodCoverage(
            samples: completeCoverageSamples,
            expectedStart: Date(timeIntervalSince1970: 0),
            expectedEnd: Date(timeIntervalSince1970: 3_600),
            expectedInterval: 30
        )
        eq(completeCoverage.fraction, 1, "continuous samples provide complete comparison coverage")
        let sparseCoverage = ThermalPeriodCoverage(
            samples: [completeCoverageSamples[0], completeCoverageSamples[completeCoverageSamples.count - 1]],
            expectedStart: Date(timeIntervalSince1970: 0),
            expectedEnd: Date(timeIntervalSince1970: 3_600),
            expectedInterval: 30
        )
        expect(sparseCoverage.fraction < 0.1, "a large gap does not masquerade as complete coverage")
        eq(comparison.current.pressureFraction, 0.5, "comparison normalizes pressure by sample count")

        // --- persisted samples and diagnostic report rendering ---
        if let encoded = try? JSONEncoder().encode(correlationSamples[0]),
           let decoded = try? JSONDecoder().decode(ThermalSample.self, from: encoded) {
            expect(decoded == correlationSamples[0], "thermal sample survives Codable round-trip")
        } else {
            expect(false, "thermal sample encodes and decodes")
        }
        let csvReport = DiagnosticReportRenderer.csv(samples: correlationSamples)
        expect(csvReport.hasPrefix("timestamp,hotspot_c"), "CSV report has stable header")
        expect(csvReport.contains("cpu_peak_c,gpu_peak_c"), "CSV report exposes component peaks")
        expect(csvReport.contains("top_process_cpu_percent"), "CSV report includes top-process CPU")
        expect(csvReport.contains("RenderApp"), "CSV report includes top process")
        let htmlReport = DiagnosticReportRenderer.html(title: "Heat <test>", samples: correlationSamples)
        expect(htmlReport.contains("Heat &lt;test&gt;"), "HTML report escapes its title")
        expect(htmlReport.contains("Likely contributors"), "HTML report includes contributor section")
        let context = DiagnosticContext(
            hardwareModel: "Mac <Test>",
            operatingSystem: "macOS Test",
            architecture: "arm64",
            processorCount: 8,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
            appVersion: "0.5.0"
        )
        let contextualReport = DiagnosticReportRenderer.html(
            title: "Diagnostic",
            samples: correlationSamples,
            context: context
        )
        expect(contextualReport.contains("System context"), "HTML report includes system context")
        expect(contextualReport.contains("Mac &lt;Test&gt;"), "HTML report escapes hardware model")

        // --- throttling assessment uses OS pressure before temperature inference ---
        let nominalState = ThermalState(name: "nominal", note: "", severity: .ok)
        let seriousState = ThermalState(name: "serious", note: "", severity: .warn)
        expect(ThrottleAssessment(hottestCelsius: 70, thermalState: nominalState).level == .normal,
               "nominal pressure and 70°C = no throttling")
        expect(ThrottleAssessment(hottestCelsius: 95, thermalState: nominalState).level == .elevated,
               "nominal pressure and 95°C = throttling risk")
        expect(ThrottleAssessment(hottestCelsius: 70, thermalState: seriousState).level == .active,
               "serious OS pressure = active throttling")

        // --- sustained alert timing, pressure edge, and cooldown ---
        let alertConfiguration = AlertConfiguration(
            enabled: true,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            cooldown: 300,
            notifyOnThermalPressure: true
        )
        var evaluator = ThermalAlertEvaluator()
        expect(evaluator.evaluate(
            sample: sample(seconds: 0, hotspot: 92),
            configuration: alertConfiguration,
            now: Date(timeIntervalSince1970: 0)
        ) == nil, "hot alert waits for sustained duration")
        expect(evaluator.evaluate(
            sample: sample(seconds: 60, hotspot: 93),
            configuration: alertConfiguration,
            now: Date(timeIntervalSince1970: 60)
        ) == .sustainedTemperature(celsius: 93), "hot alert fires after sustained duration")
        expect(evaluator.evaluate(
            sample: sample(seconds: 70, hotspot: 94),
            configuration: alertConfiguration,
            now: Date(timeIntervalSince1970: 70)
        ) == nil, "alert cooldown suppresses repeats")

        var pressureEvaluator = ThermalAlertEvaluator()
        expect(pressureEvaluator.evaluate(
            sample: sample(seconds: 0, hotspot: 70, severity: .warn),
            configuration: alertConfiguration,
            now: Date(timeIntervalSince1970: 0)
        ) == .thermalPressure(state: "serious"), "pressure alert fires on serious transition")

        // --- automatic pressure incidents and delayed recovery ---
        var incidentDetector = AutomaticIncidentDetector()
        expect(incidentDetector.evaluate(
            sample: sample(seconds: 0, hotspot: 82, severity: .warn),
            pressureEnabled: true,
            temperatureEnabled: false,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 0)
        ) == .start(trigger: .automaticThermalPressure, state: "serious", severity: .warn),
               "serious pressure starts an automatic incident")
        expect(incidentDetector.evaluate(
            sample: sample(seconds: 10, hotspot: 70),
            pressureEnabled: true,
            temperatureEnabled: false,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 10)
        ) == nil, "automatic incident waits through recovery grace period")
        expect(incidentDetector.evaluate(
            sample: sample(seconds: 70, hotspot: 68),
            pressureEnabled: true,
            temperatureEnabled: false,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 70)
        ) == .stop, "automatic incident stops after sustained recovery")

        var disabledDetector = AutomaticIncidentDetector()
        _ = disabledDetector.evaluate(
            sample: sample(seconds: 0, hotspot: 82, severity: .critical),
            pressureEnabled: true,
            temperatureEnabled: false,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 0)
        )
        expect(disabledDetector.evaluate(
            sample: sample(seconds: 1, hotspot: 82, severity: .critical),
            pressureEnabled: false,
            temperatureEnabled: false,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 1)
        ) == .stop, "disabling automatic capture stops its active incident")

        var hotIncidentDetector = AutomaticIncidentDetector()
        expect(hotIncidentDetector.evaluate(
            sample: sample(seconds: 0, hotspot: 92),
            pressureEnabled: false,
            temperatureEnabled: true,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 0)
        ) == nil, "high-temperature incident waits for sustained duration")
        expect(hotIncidentDetector.evaluate(
            sample: sample(seconds: 60, hotspot: 93),
            pressureEnabled: false,
            temperatureEnabled: true,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 60)
        ) == .start(trigger: .automaticHighTemperature, state: "nominal", severity: .ok),
               "sustained high temperature starts an automatic incident even with nominal pressure")
        expect(hotIncidentDetector.evaluate(
            sample: sample(seconds: 70, hotspot: 88),
            pressureEnabled: false,
            temperatureEnabled: true,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 70)
        ) == nil, "temperature recovery margin prevents early incident stop")
        expect(hotIncidentDetector.evaluate(
            sample: sample(seconds: 80, hotspot: 86),
            pressureEnabled: false,
            temperatureEnabled: true,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 80)
        ) == nil, "temperature incident begins recovery below the hysteresis margin")
        expect(hotIncidentDetector.evaluate(
            sample: sample(seconds: 140, hotspot: 85),
            pressureEnabled: false,
            temperatureEnabled: true,
            thresholdCelsius: 90,
            sustainedDuration: 60,
            recoveryDuration: 60,
            now: Date(timeIntervalSince1970: 140)
        ) == .stop, "temperature incident stops after sustained recovery")

        // --- derived event timeline with threshold hysteresis ---
        let eventSamples = [
            sample(seconds: 0, hotspot: 80),
            sample(seconds: 10, hotspot: 91),
            sample(seconds: 20, hotspot: 89),
            sample(seconds: 30, hotspot: 86),
            sample(seconds: 40, hotspot: 82, severity: .warn),
            sample(seconds: 50, hotspot: 84, severity: .critical),
            sample(seconds: 60, hotspot: 72),
        ]
        let events = ThermalEventAnalyzer.events(samples: eventSamples, thresholdCelsius: 90)
        expect(events.map(\.kind) == [
            .pressureRecovered,
            .pressureEscalated,
            .pressureBegan,
            .temperatureRecovered,
            .temperatureExceeded,
        ], "timeline records threshold, pressure escalation, and recovery in newest-first order")

        let preRoll = ThermalIncidentPreRoll.samples(
            from: eventSamples,
            endingAt: Date(timeIntervalSince1970: 50),
            duration: 25
        )
        expect(preRoll.map { $0.timestamp.timeIntervalSince1970 } == [30, 40, 50],
               "automatic incident pre-roll includes only the configured lead-up window")

        // --- incident provenance, renaming, and backward-compatible decoding ---
        let incident = ThermalIncident(
            name: "Before",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            samples: eventSamples,
            trigger: .automaticThermalPressure
        )
        let renamedIncident = incident.renamed(to: "Export workload")
        expect(renamedIncident.id == incident.id && renamedIncident.name == "Export workload",
               "renaming preserves incident identity and samples")
        if let encodedIncident = try? JSONEncoder().encode(incident),
           var object = try? JSONSerialization.jsonObject(with: encodedIncident) as? [String: Any] {
            object.removeValue(forKey: "trigger")
            if let legacyData = try? JSONSerialization.data(withJSONObject: object),
               let legacyIncident = try? JSONDecoder().decode(ThermalIncident.self, from: legacyData) {
                expect(legacyIncident.effectiveTrigger == .manual, "legacy incidents without provenance decode as manual")
            } else {
                expect(false, "legacy incident JSON decodes")
            }
        } else {
            expect(false, "incident JSON encodes for compatibility test")
        }

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

        // --- FourCharCode helpers (round-trip + short-key space padding) ---
        expect(fourCharString(fourCharCode("TC0P")) == "TC0P", "fourChar round-trips a full 4-char key")
        expect(fourCharCode("TC0P") == 0x54_43_30_50, "fourCharCode packs big-endian ASCII")
        expect(fourCharString(fourCharCode("FNum")) == "FNum", "fourChar round-trips FNum")
        expect(fourCharString(fourCharCode("F0")) == "F0  ", "fourCharCode space-pads a short key to 4 bytes")

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
