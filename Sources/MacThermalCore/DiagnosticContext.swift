import Foundation

public struct DiagnosticContext: Equatable, Sendable {
    public let hardwareModel: String
    public let operatingSystem: String
    public let architecture: String
    public let processorCount: Int
    public let physicalMemoryBytes: UInt64
    public let appVersion: String

    public init(
        hardwareModel: String,
        operatingSystem: String,
        architecture: String,
        processorCount: Int,
        physicalMemoryBytes: UInt64,
        appVersion: String
    ) {
        self.hardwareModel = hardwareModel
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.processorCount = processorCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.appVersion = appVersion
    }
}
