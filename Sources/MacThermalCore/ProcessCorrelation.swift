import Foundation

/// Statistical association between a process' sampled CPU use and hotspot
/// temperature. This is an investigative hint, not proof that the process
/// caused the heat.
public struct ProcessCorrelation: Equatable, Identifiable, Sendable {
    public let processName: String
    public let coefficient: Double
    public let averageCPUPercent: Double
    public let peakCPUPercent: Double
    public let samplesObserved: Int

    public var id: String { processName }

    public init(
        processName: String,
        coefficient: Double,
        averageCPUPercent: Double,
        peakCPUPercent: Double,
        samplesObserved: Int
    ) {
        self.processName = processName
        self.coefficient = coefficient
        self.averageCPUPercent = averageCPUPercent
        self.peakCPUPercent = peakCPUPercent
        self.samplesObserved = samplesObserved
    }
}
