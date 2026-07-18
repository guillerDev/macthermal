import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

/// Keeps history scans and correlation math off the main actor. The value
/// models crossing this boundary are immutable and Sendable.
actor AnalyticsEngine {
    static let shared = AnalyticsEngine()

    func recentSamples(_ samples: [ThermalSample], since cutoff: Date) -> [ThermalSample] {
        samples.filter { $0.timestamp >= cutoff }
    }

    func temperatureChartSamples(
        _ samples: [ThermalSample],
        maximumCount: Int
    ) -> [ThermalSample] {
        ThermalSampleDownsampler.samples(from: samples, maximumCount: maximumCount)
    }

    func processCorrelations(_ samples: [ThermalSample]) -> [ProcessCorrelation] {
        ThermalAnalytics.processCorrelations(samples: samples)
    }

    func events(_ samples: [ThermalSample], thresholdCelsius: Double) -> [ThermalEvent] {
        ThermalEventAnalyzer.events(samples: samples, thresholdCelsius: thresholdCelsius)
    }

    func comparison(
        samples: [ThermalSample],
        currentEnd: Date,
        duration: TimeInterval
    ) -> ThermalComparison {
        let currentStart = currentEnd.addingTimeInterval(-duration)
        let baselineStart = currentStart.addingTimeInterval(-duration)
        let baseline = samples.filter { $0.timestamp >= baselineStart && $0.timestamp < currentStart }
        let current = samples.filter { $0.timestamp >= currentStart && $0.timestamp <= currentEnd }
        return ThermalComparison(baselineSamples: baseline, currentSamples: current)
    }
}
