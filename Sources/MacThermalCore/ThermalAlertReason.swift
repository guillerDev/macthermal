import Foundation

public enum ThermalAlertReason: Equatable, Sendable {
    case sustainedTemperature(celsius: Double)
    case thermalPressure(state: String)
}
