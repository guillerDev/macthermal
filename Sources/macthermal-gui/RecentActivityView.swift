import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct RecentActivityView: View {
    let samples: [ThermalSample]
    let unit: TempUnit
    @Binding var scope: TemperatureChartScope

    var body: some View {
        GroupBox("Recent activity") {
            if samples.count < 2 {
                Text("History will appear after the next samples are recorded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                TemperatureHistoryChart(
                    samples: samples,
                    unit: unit,
                    alertThresholdCelsius: nil,
                    scope: $scope
                )
                    .frame(minHeight: 220)
            }
        }
    }
}
