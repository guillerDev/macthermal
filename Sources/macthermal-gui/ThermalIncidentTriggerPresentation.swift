#if canImport(MacThermalCore)
import MacThermalCore
#endif

extension ThermalIncidentTrigger {
    var helpText: String {
        switch self {
        case .manual: "Recorded manually"
        case .automaticThermalPressure: "Captured automatically from macOS thermal pressure"
        case .automaticHighTemperature: "Captured automatically from sustained high temperature"
        }
    }
}
