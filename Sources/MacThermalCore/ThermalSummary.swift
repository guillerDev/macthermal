import Foundation

public struct ThermalSummary: Equatable, Sendable {
    public let sampleCount: Int
    public let averageHotspotCelsius: Double
    public let peakHotspotCelsius: Double
    public let averageFanUtilization: Double
    public let pressureSampleCount: Int
    public let pressureFraction: Double

    public init(samples: [ThermalSample]) {
        sampleCount = samples.count
        guard !samples.isEmpty else {
            averageHotspotCelsius = 0
            peakHotspotCelsius = 0
            averageFanUtilization = 0
            pressureSampleCount = 0
            pressureFraction = 0
            return
        }

        var hotspotSum = 0.0
        var peakHotspot = -Double.infinity
        var fanSum = 0.0
        var pressureCount = 0
        for sample in samples {
            hotspotSum += sample.hottestCelsius
            peakHotspot = max(peakHotspot, sample.hottestCelsius)
            fanSum += sample.averageFanUtilization
            if sample.thermalSeverity == .warn || sample.thermalSeverity == .critical {
                pressureCount += 1
            }
        }
        let count = Double(samples.count)
        averageHotspotCelsius = hotspotSum / count
        peakHotspotCelsius = peakHotspot
        averageFanUtilization = fanSum / count
        pressureSampleCount = pressureCount
        pressureFraction = Double(pressureCount) / count
    }
}
