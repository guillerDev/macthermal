import Foundation

public struct ThermalSummary: Equatable, Sendable {
    public let sampleCount: Int
    public let averageHotspotCelsius: Double
    public let peakHotspotCelsius: Double
    public let averageFanUtilization: Double
    public let pressureSampleCount: Int

    public init(samples: [ThermalSample]) {
        sampleCount = samples.count
        guard !samples.isEmpty else {
            averageHotspotCelsius = 0
            peakHotspotCelsius = 0
            averageFanUtilization = 0
            pressureSampleCount = 0
            return
        }

        averageHotspotCelsius = samples.map(\.hottestCelsius).reduce(0, +) / Double(samples.count)
        peakHotspotCelsius = samples.map(\.hottestCelsius).max() ?? 0
        averageFanUtilization = samples.map(\.averageFanUtilization).reduce(0, +) / Double(samples.count)
        pressureSampleCount = samples.count {
            $0.thermalSeverity == .warn || $0.thermalSeverity == .critical
        }
    }
}
