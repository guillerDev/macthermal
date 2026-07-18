import Foundation

public enum ComparisonTrend: Equatable, Sendable {
    case improved
    case regressed
    case unchanged
    case contextual
}

public enum ThermalComparisonResult: Equatable, Sendable {
    case improved
    case regressed
    case mixed
    case unchanged
}

public struct ThermalComparisonAssessment: Equatable, Sendable {
    public let averageHotspotTrend: ComparisonTrend
    public let peakHotspotTrend: ComparisonTrend
    public let fanTrend: ComparisonTrend
    public let pressureTrend: ComparisonTrend
    public let result: ThermalComparisonResult

    public init(comparison: ThermalComparison) {
        let averageTrend = Self.lowerIsBetter(
            delta: comparison.hotspotDeltaCelsius,
            tolerance: 1
        )
        let peakTrend = Self.lowerIsBetter(
            delta: comparison.peakDeltaCelsius,
            tolerance: 2
        )
        let pressureTrend = Self.lowerIsBetter(
            delta: comparison.pressureFractionDelta,
            tolerance: 0.01
        )
        let fanTrend: ComparisonTrend
        if !comparison.fanDataAvailable {
            fanTrend = .contextual
        } else if abs(comparison.fanDeltaPercent) <= 3 {
            fanTrend = .unchanged
        } else {
            // Fan effort is context, not a standalone success or regression:
            // more cooling can accompany a lower temperature and vice versa.
            fanTrend = .contextual
        }

        averageHotspotTrend = averageTrend
        peakHotspotTrend = peakTrend
        self.fanTrend = fanTrend
        self.pressureTrend = pressureTrend

        let directionalTrends = [averageTrend, peakTrend, pressureTrend]
        let hasImprovement = directionalTrends.contains(.improved)
        let hasRegression = directionalTrends.contains(.regressed)
        if hasImprovement && hasRegression {
            result = .mixed
        } else if hasRegression {
            result = .regressed
        } else if hasImprovement {
            result = .improved
        } else {
            result = .unchanged
        }
    }

    private static func lowerIsBetter(delta: Double, tolerance: Double) -> ComparisonTrend {
        if delta < -tolerance { return .improved }
        if delta > tolerance { return .regressed }
        return .unchanged
    }
}
