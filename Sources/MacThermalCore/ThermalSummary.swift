import Foundation

public struct ThermalSummary: Equatable, Sendable {
    public let sampleCount: Int
    public let averageHotspotCelsius: Double
    public let peakHotspotCelsius: Double
    public let averageFanUtilization: Double
    public let fanSampleCount: Int
    public let pressureSampleCount: Int
    public let pressureFraction: Double

    public var hasFanData: Bool { fanSampleCount > 0 }

    public init(samples: [ThermalSample]) {
        sampleCount = samples.count
        guard !samples.isEmpty else {
            averageHotspotCelsius = 0
            peakHotspotCelsius = 0
            averageFanUtilization = 0
            fanSampleCount = 0
            pressureSampleCount = 0
            pressureFraction = 0
            return
        }

        var hotspotSum = 0.0
        var peakHotspot = -Double.infinity
        var fanSum = 0.0
        var samplesWithFans = 0
        var pressureCount = 0
        for sample in samples {
            hotspotSum += sample.hottestCelsius
            peakHotspot = max(peakHotspot, sample.hottestCelsius)
            if !sample.fanUtilization.isEmpty {
                fanSum += sample.averageFanUtilization
                samplesWithFans += 1
            }
            if sample.thermalSeverity == .warn || sample.thermalSeverity == .critical {
                pressureCount += 1
            }
        }
        let count = Double(samples.count)
        averageHotspotCelsius = hotspotSum / count
        peakHotspotCelsius = peakHotspot
        averageFanUtilization = samplesWithFans > 0 ? fanSum / Double(samplesWithFans) : 0
        fanSampleCount = samplesWithFans
        pressureSampleCount = pressureCount
        pressureFraction = Double(pressureCount) / count
    }
}
