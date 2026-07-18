import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
typealias ThermalCategory = MacThermalCore.Category
#else
typealias ThermalCategory = Category
#endif

struct TempGroup: Equatable, Identifiable {
    let category: ThermalCategory
    let readings: [TempReading]
    let hottest: TempReading
    let averageCelsius: Double

    var id: ThermalCategory { category }

    static func grouped(_ temperatures: [TempReading]) -> [TempGroup] {
        let grouped = Dictionary(grouping: temperatures, by: \.category)
        return ThermalCategory.allCases.compactMap { category in
            guard let readings = grouped[category], let hottest = readings.first else { return nil }
            return TempGroup(
                category: category,
                readings: readings,
                hottest: hottest,
                averageCelsius: readings.averageCelsius
            )
        }
    }
}
