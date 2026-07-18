import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

extension Severity {
    var color: Color {
        switch self {
        case .ok, .normal: .green
        case .warn: .yellow
        case .hot: .orange
        case .critical: .red
        }
    }

    var symbol: String {
        switch self {
        case .ok, .normal: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .hot: "flame.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

extension ThrottleLevel {
    var color: Color {
        switch self {
        case .normal: .green
        case .elevated: .yellow
        case .active: .orange
        case .critical: .red
        }
    }

    var symbol: String {
        switch self {
        case .normal: "checkmark.shield.fill"
        case .elevated: "thermometer.high"
        case .active: "gauge.with.dots.needle.67percent"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
