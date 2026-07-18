import Foundation
import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

extension ThermalEventKind {
    var title: String {
        switch self {
        case .temperatureExceeded: "Temperature threshold exceeded"
        case .temperatureRecovered: "Temperature recovered"
        case .pressureBegan: "Thermal throttling began"
        case .pressureEscalated: "Thermal pressure became critical"
        case .pressureRecovered: "Thermal pressure recovered"
        }
    }

    var symbol: String {
        switch self {
        case .temperatureExceeded: "thermometer.high"
        case .temperatureRecovered: "thermometer.low"
        case .pressureBegan: "gauge.with.dots.needle.67percent"
        case .pressureEscalated: "exclamationmark.octagon.fill"
        case .pressureRecovered: "checkmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .temperatureExceeded: .orange
        case .temperatureRecovered, .pressureRecovered: .green
        case .pressureBegan: .orange
        case .pressureEscalated: .red
        }
    }
}

extension ThermalEvent {
    func detail(unit: TempUnit) -> String {
        switch kind {
        case .temperatureExceeded:
            let threshold = thresholdCelsius.map { unit.format($0) } ?? "the configured threshold"
            return "Hotspot reached \(unit.format(hottestCelsius)), above \(threshold)."
        case .temperatureRecovered:
            return "Hotspot fell to \(unit.format(hottestCelsius)) and cleared the recovery margin."
        case .pressureBegan:
            return "macOS reported \(thermalStateName) pressure at \(unit.format(hottestCelsius))."
        case .pressureEscalated:
            return "macOS escalated to critical pressure at \(unit.format(hottestCelsius))."
        case .pressureRecovered:
            return "macOS returned to \(thermalStateName) pressure at \(unit.format(hottestCelsius))."
        }
    }
}
