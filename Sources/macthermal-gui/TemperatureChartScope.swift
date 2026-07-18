import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

enum TemperatureChartScope: String, CaseIterable, Identifiable, Sendable {
    case overall
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case battery = "Battery"
    case ambient = "Ambient"
    case other = "Other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overall: "Overall"
        default: rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .overall: "thermometer.variable"
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        case .battery: "battery.75percent"
        case .ambient: "thermometer.medium"
        case .other: "sensor"
        }
    }

    func hotspot(in sample: ThermalSample) -> Double? {
        switch self {
        case .overall: sample.hottestCelsius
        default: sample.categoryPeaks[rawValue]
        }
    }

    func average(in sample: ThermalSample) -> Double? {
        switch self {
        case .overall: sample.averageCelsius
        default: sample.categoryAverages?[rawValue]
        }
    }

    static func available(in samples: [ThermalSample]) -> [TemperatureChartScope] {
        var categoryKeys = Set<String>()
        for sample in samples {
            categoryKeys.formUnion(sample.categoryPeaks.keys)
        }
        return allCases.filter { scope in
            scope == .overall || categoryKeys.contains(scope.rawValue)
        }
    }
}
