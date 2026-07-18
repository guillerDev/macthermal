import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct TemperatureBreakdownView: View {
    let groups: [TempGroup]
    let unit: TempUnit

    var body: some View {
        GroupBox("Temperature by component") {
            Grid(alignment: .leading, horizontalSpacing: DesignMetrics.sectionSpacing, verticalSpacing: DesignMetrics.standardSpacing) {
                GridRow {
                    Text("Component").foregroundStyle(.secondary)
                    Text("Hotspot").foregroundStyle(.secondary)
                    Text("Average").foregroundStyle(.secondary)
                    Text("Sensors").foregroundStyle(.secondary)
                }
                Divider()
                ForEach(groups) { group in
                    let level = tempLevel(group.hottest.celsius)
                    GridRow {
                        Label(group.category.rawValue, systemImage: categorySymbol(group.category.rawValue))
                        Label(unit.format(group.hottest.celsius), systemImage: level.severity.symbol)
                            .foregroundStyle(level.severity.color)
                        Text(unit.format(group.averageCelsius))
                        Text(group.readings.count, format: .number)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DesignMetrics.compactSpacing)
        }
    }

    private func categorySymbol(_ category: String) -> String {
        switch category {
        case "CPU": "cpu"
        case "GPU": "rectangle.3.group"
        case "Memory": "memorychip"
        case "Battery": "battery.75percent"
        case "Ambient": "thermometer.low"
        default: "sensor"
        }
    }
}
