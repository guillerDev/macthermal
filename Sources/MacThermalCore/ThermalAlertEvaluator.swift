import Foundation

public struct ThermalAlertEvaluator: Sendable {
    private var hotSince: Date?
    private var lastNotificationAt: Date?
    private var pressureWasActive = false

    public init() {}

    public mutating func evaluate(
        sample: ThermalSample,
        configuration: AlertConfiguration,
        now: Date
    ) -> ThermalAlertReason? {
        guard configuration.enabled else {
            hotSince = nil
            pressureWasActive = false
            return nil
        }

        let coolingDown = lastNotificationAt.map {
            now.timeIntervalSince($0) < configuration.cooldown
        } ?? false

        let pressureIsActive = sample.thermalSeverity == .warn || sample.thermalSeverity == .critical
        defer { pressureWasActive = pressureIsActive }
        if configuration.notifyOnThermalPressure,
           pressureIsActive,
           !pressureWasActive,
           !coolingDown {
            lastNotificationAt = now
            return .thermalPressure(state: sample.thermalStateName)
        }

        guard sample.hottestCelsius >= configuration.thresholdCelsius else {
            hotSince = nil
            return nil
        }

        if hotSince == nil { hotSince = now }
        guard let hotSince,
              now.timeIntervalSince(hotSince) >= configuration.sustainedDuration,
              !coolingDown else { return nil }

        lastNotificationAt = now
        return .sustainedTemperature(celsius: sample.hottestCelsius)
    }
}
