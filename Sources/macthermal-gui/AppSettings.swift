import Combine
import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

@MainActor
final class AppSettings: ObservableObject {
    @Published var unit: TempUnit { didSet { save(unit.rawValue, for: "temperatureUnit") } }
    @Published var menuBarMetric: MenuBarMetric { didSet { save(menuBarMetric.rawValue, for: "menuBarMetric") } }
    @Published var historyInterval: TimeInterval { didSet { save(historyInterval, for: "historyInterval") } }
    @Published var retentionDays: Int { didSet { save(retentionDays, for: "retentionDays") } }
    @Published var alertsEnabled: Bool { didSet { save(alertsEnabled, for: "alertsEnabled") } }
    @Published var alertThresholdCelsius: Double { didSet { save(alertThresholdCelsius, for: "alertThresholdCelsius") } }
    @Published var sustainedAlertSeconds: TimeInterval { didSet { save(sustainedAlertSeconds, for: "sustainedAlertSeconds") } }
    @Published var alertCooldownMinutes: Double { didSet { save(alertCooldownMinutes, for: "alertCooldownMinutes") } }
    @Published var notifyOnThermalPressure: Bool { didSet { save(notifyOnThermalPressure, for: "notifyOnThermalPressure") } }
    @Published var autoRecordPressureIncidents: Bool { didSet { save(autoRecordPressureIncidents, for: "autoRecordPressureIncidents") } }
    @Published var autoRecordTemperatureIncidents: Bool { didSet { save(autoRecordTemperatureIncidents, for: "autoRecordTemperatureIncidents") } }
    @Published var automaticIncidentRecoverySeconds: TimeInterval { didSet { save(automaticIncidentRecoverySeconds, for: "automaticIncidentRecoverySeconds") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unit = TempUnit(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        menuBarMetric = MenuBarMetric(rawValue: defaults.string(forKey: "menuBarMetric") ?? "") ?? .hotspot
        historyInterval = defaults.object(forKey: "historyInterval") as? TimeInterval ?? 30
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 7
        alertsEnabled = defaults.object(forKey: "alertsEnabled") as? Bool ?? true
        alertThresholdCelsius = defaults.object(forKey: "alertThresholdCelsius") as? Double ?? 90
        sustainedAlertSeconds = defaults.object(forKey: "sustainedAlertSeconds") as? TimeInterval ?? 60
        alertCooldownMinutes = defaults.object(forKey: "alertCooldownMinutes") as? Double ?? 15
        notifyOnThermalPressure = defaults.object(forKey: "notifyOnThermalPressure") as? Bool ?? true
        autoRecordPressureIncidents = defaults.object(forKey: "autoRecordPressureIncidents") as? Bool ?? true
        autoRecordTemperatureIncidents = defaults.object(forKey: "autoRecordTemperatureIncidents") as? Bool ?? true
        automaticIncidentRecoverySeconds = defaults.object(forKey: "automaticIncidentRecoverySeconds") as? TimeInterval ?? 60
    }

    var alertConfiguration: AlertConfiguration {
        AlertConfiguration(
            enabled: alertsEnabled,
            thresholdCelsius: alertThresholdCelsius,
            sustainedDuration: sustainedAlertSeconds,
            cooldown: alertCooldownMinutes * 60,
            notifyOnThermalPressure: notifyOnThermalPressure
        )
    }

    private func save(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
    }
}
