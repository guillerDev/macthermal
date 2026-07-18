import Foundation

public struct ThermalComparison: Equatable, Sendable {
    public let baseline: ThermalSummary
    public let current: ThermalSummary

    public init(baselineSamples: [ThermalSample], currentSamples: [ThermalSample]) {
        baseline = ThermalSummary(samples: baselineSamples)
        current = ThermalSummary(samples: currentSamples)
    }

    public var hotspotDeltaCelsius: Double {
        current.averageHotspotCelsius - baseline.averageHotspotCelsius
    }

    public var peakDeltaCelsius: Double {
        current.peakHotspotCelsius - baseline.peakHotspotCelsius
    }

    public var fanDeltaPercent: Double {
        current.averageFanUtilization - baseline.averageFanUtilization
    }

    public var fanDataAvailable: Bool {
        baseline.hasFanData && current.hasFanData
    }

    public var pressureFractionDelta: Double {
        current.pressureFraction - baseline.pressureFraction
    }
}

public struct ThermalPeriodCoverage: Equatable, Sendable {
    public let sampleCount: Int
    public let coveredDuration: TimeInterval
    public let expectedDuration: TimeInterval

    public var fraction: Double {
        guard expectedDuration > 0 else { return 0 }
        return min(1, coveredDuration / expectedDuration)
    }

    public init(
        samples: [ThermalSample],
        expectedStart: Date,
        expectedEnd: Date,
        expectedInterval: TimeInterval
    ) {
        sampleCount = samples.count
        expectedDuration = max(0, expectedEnd.timeIntervalSince(expectedStart))
        guard samples.count > 1, expectedDuration > 0 else {
            coveredDuration = 0
            return
        }

        let maximumCreditedGap = max(1, expectedInterval) * 2
        var covered = 0.0
        for index in 1..<samples.count {
            let previous = samples[index - 1].timestamp
            let current = samples[index].timestamp
            let interval = current.timeIntervalSince(previous)
            if interval > 0 {
                covered += min(interval, maximumCreditedGap)
            }
        }
        coveredDuration = min(expectedDuration, covered)
    }
}
