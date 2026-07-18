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
}
