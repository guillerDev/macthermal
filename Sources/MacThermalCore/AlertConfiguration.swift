import Foundation

public struct AlertConfiguration: Equatable, Sendable {
    public let enabled: Bool
    public let thresholdCelsius: Double
    public let sustainedDuration: TimeInterval
    public let cooldown: TimeInterval
    public let notifyOnThermalPressure: Bool

    public init(
        enabled: Bool,
        thresholdCelsius: Double,
        sustainedDuration: TimeInterval,
        cooldown: TimeInterval,
        notifyOnThermalPressure: Bool
    ) {
        self.enabled = enabled
        self.thresholdCelsius = thresholdCelsius
        self.sustainedDuration = sustainedDuration
        self.cooldown = cooldown
        self.notifyOnThermalPressure = notifyOnThermalPressure
    }
}
