import Charts
import SwiftUI
#if canImport(MacThermalCore)
import MacThermalCore
#endif

struct ContributorsChart: View {
    let correlations: [ProcessCorrelation]

    var body: some View {
        Chart(correlations) { item in
            BarMark(
                x: .value("Correlation", max(0, item.coefficient)),
                y: .value("Process", item.processName)
            )
            .foregroundStyle(by: .value("Process", item.processName))
            .annotation(position: .trailing) {
                Text(item.coefficient, format: .number.precision(.fractionLength(2)))
                    .font(.callout)
            }
        }
        .chartXScale(domain: 0...1)
        .chartLegend(.hidden)
        .accessibilityLabel("Process heat correlations")
    }
}
