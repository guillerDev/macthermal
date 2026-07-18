import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case hotspot
    case cpu
    case gpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotspot: "Hottest sensor"
        case .cpu: "CPU hotspot"
        case .gpu: "GPU hotspot"
        }
    }

    var category: ThermalCategory? {
        switch self {
        case .hotspot: nil
        case .cpu: .cpu
        case .gpu: .gpu
        }
    }
}
