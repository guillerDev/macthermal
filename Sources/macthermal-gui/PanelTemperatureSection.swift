import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct PanelTemperatureSection: View {
    let groups: [TempGroup]
    let unit: TempUnit

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: DesignMetrics.standardSpacing, verticalSpacing: DesignMetrics.compactSpacing) {
            ForEach(groups) { group in
                let level = tempLevel(group.hottest.celsius)
                GridRow {
                    Text(group.category.rawValue)
                    Label(unit.format(group.hottest.celsius), systemImage: level.severity.symbol)
                        .bold()
                        .foregroundStyle(level.severity.color)
                    Text("avg \(unit.format(group.averageCelsius))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
