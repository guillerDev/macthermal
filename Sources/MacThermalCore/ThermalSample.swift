import Foundation

/// A compact, persistable snapshot used by charts, reports, comparisons, and
/// incident recordings. Raw per-key readings remain available in the live UI;
/// history stores category peaks to keep its on-disk footprint bounded.
public struct ThermalSample: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let hottestCelsius: Double
    public let averageCelsius: Double
    public let categoryPeaks: [String: Double]
    public let fanRPM: [Double]
    public let fanUtilization: [Double]
    public let thermalStateName: String
    public let thermalSeverity: Severity
    public let topProcesses: [ProcessUsage]

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        hottestCelsius: Double,
        averageCelsius: Double,
        categoryPeaks: [String: Double],
        fanRPM: [Double],
        fanUtilization: [Double],
        thermalStateName: String,
        thermalSeverity: Severity,
        topProcesses: [ProcessUsage]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hottestCelsius = hottestCelsius
        self.averageCelsius = averageCelsius
        self.categoryPeaks = categoryPeaks
        self.fanRPM = fanRPM
        self.fanUtilization = fanUtilization
        self.thermalStateName = thermalStateName
        self.thermalSeverity = thermalSeverity
        self.topProcesses = topProcesses
    }

    public init(snapshot: Snapshot, processes: [ProcessUsage], timestamp: Date = .now) {
        var peaks: [String: Double] = [:]
        for category in Category.allCases {
            if let hottest = snapshot.group(category).first?.celsius {
                peaks[category.rawValue] = hottest
            }
        }

        self.init(
            timestamp: timestamp,
            hottestCelsius: snapshot.hottest?.celsius ?? 0,
            averageCelsius: snapshot.averageC,
            categoryPeaks: peaks,
            fanRPM: snapshot.fans.map(\.rpm),
            fanUtilization: snapshot.fans.map(\.utilization),
            thermalStateName: snapshot.thermal.name,
            thermalSeverity: snapshot.thermal.severity,
            topProcesses: processes
        )
    }

    public var averageFanUtilization: Double {
        fanUtilization.isEmpty ? 0 : fanUtilization.reduce(0, +) / Double(fanUtilization.count)
    }
}
