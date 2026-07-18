import Foundation

public enum ThermalIncidentPreRoll {
    public static func samples(
        from history: [ThermalSample],
        endingAt date: Date,
        duration: TimeInterval
    ) -> [ThermalSample] {
        let start = date.addingTimeInterval(-max(0, duration))
        return history
            .filter { $0.timestamp >= start && $0.timestamp <= date }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
